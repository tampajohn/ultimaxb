import AppKit
import UOCore

@MainActor
final class MapPanel:NSView {
    private let assets:ClientAssets
    private let artwork:Sprite?
    private var player:WorldMobile?
    private var mobiles:[WorldMobile] = []
    private var world = false
    private var terrain:Sprite?
    private var image:NSImage?
    private var origin = (0,0)
    private var renderedKey:String?
    private var drag:NSPoint?
    private var signs:[WorldTile] = []
    var groundItems:[GroundItem] = [] { didSet { needsDisplay = true } }
    private func signName(_ graphic:Int)->String? {
        guard (0xBA3...0xBCE).contains(graphic) || (0xBD3...0xC0E).contains(graphic) else { return nil }
        return try? assets.itemName(graphic:graphic)
    }
    private func mapContains(_ point:NSPoint)->Bool {
        guard let artwork else { return false }
        let x=Int(point.x), y=Int(point.y)
        guard x>=0,y>=0,x<artwork.width,y<artwork.height else { return false }
        let i=(y*artwork.width+x)*4
        return artwork.rgba[i] == 8 && artwork.rgba[i+1] == 8 && artwork.rgba[i+2] == 8
    }
    var combatTarget:UInt32? { didSet { needsDisplay = true } }
    var onTravel: ((Int,Int)->Void)?
    override var isFlipped:Bool { true }
    init(assets:ClientAssets) {
        self.assets = assets
        artwork = try? assets.gumps?.sprite(0x1393)
        super.init(frame:NSRect(x:300,y:32,width:280,height:280))
        toolTip = "Map · White: you · Red: enemies/target · Blue: innocent · Green: ally · Gray: neutral\nShift-click: travel · Double-click: Local/World · Right-click or M: close · Drag to move"
        setAccessibilityLabel("Map. Double-click to switch Local and World views.")
    }
    required init?(coder:NSCoder) { fatalError() }
    func toggleMode() {
        world.toggle(); renderedKey = nil; update(player:player,mobiles:mobiles)
        Telemetry.shared.record("map_mode",["world":world])
    }
    private var overviewRect:NSRect {
        let width:CGFloat = 180, height = width*CGFloat(assets.height)/CGFloat(assets.width)
        return NSRect(x:50,y:(280-height)/2,width:width,height:height)
    }
    func update(player:WorldMobile?,mobiles:[WorldMobile]) {
        self.player = player; self.mobiles = mobiles
        guard let player else { removeFromSuperview(); return }
        let x = world ? 0 : (player.x/8)*8-96
        let y = world ? 0 : (player.y/8)*8-96
        let key = "\(world):\(x):\(y)"
        do {
            if key != renderedKey {
                origin = (x,y)
                signs = world ? [] : try assets.region(x:player.x,y:player.y,radius:64).filter { signName($0.art-0x4000) != nil }
                terrain = try assets.radar?.render(x:x,y:y,pixelWidth:world ? assets.width/16 : 192,
                                                 pixelHeight:world ? assets.height/16 : 192,step:world ? 16 : 1)
                renderedKey = key
            }
            if !world, let artwork, let terrain {
                image = Self.image(try RadarWidget.compose(frame:artwork,terrain:terrain,
                        centerX:player.x-origin.0,centerY:player.y-origin.1))
            } else { image = terrain.flatMap(Self.image) }
        } catch { image = nil; Telemetry.shared.record("map_render_failed") }
        needsDisplay = true
    }
    private static func image(_ sprite:Sprite)->NSImage? {
        guard let provider = CGDataProvider(data:Data(sprite.rgba) as CFData),
              let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,
                               bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,
                               decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if world {
            if let artwork { Self.image(artwork)?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            image?.draw(in:overviewRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        } else { image?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        guard let player else { return }
        func point(_ mobile:WorldMobile)->NSPoint {
            if world {
                return NSPoint(x:overviewRect.minX+CGFloat(mobile.x)/CGFloat(assets.width)*overviewRect.width,
                               y:overviewRect.minY+CGFloat(mobile.y)/CGFloat(assets.height)*overviewRect.height)
            }
            let dx = mobile.x-player.x, dy = mobile.y-player.y
            return NSPoint(x:140+dx-dy,y:140+dx+dy)
        }
        if !world {
            var landmarks = signs.map { ($0.x,$0.y,$0.art-0x4000) }
            landmarks += groundItems.filter { signName($0.graphic) != nil }.map { ($0.x,$0.y,$0.graphic) }
            func priority(_ graphic:Int)->Int { (0xC0B...0xC0C).contains(graphic) ? 0 : (0xBC7...0xBC8).contains(graphic) ? 1 : 2 }
            landmarks.sort {
                let a=priority($0.2), b=priority($1.2)
                return a == b ? abs($0.0-player.x)+abs($0.1-player.y) < abs($1.0-player.x)+abs($1.1-player.y) : a < b
            }
            var occupied:[NSRect] = [], seen=Set<String>()
            for (x,y,graphic) in landmarks {
                guard occupied.count < 6, let name=signName(graphic) else { continue }
                let key="\(x):\(y):\(name)"
                guard seen.insert(key).inserted else { continue }
                let p=NSPoint(x:140+(x-player.x)-(y-player.y),y:140+(x-player.x)+(y-player.y))
                let text=name as NSString
                let attributes:[NSAttributedString.Key:Any] = [.font:NSFont.boldSystemFont(ofSize:10),.foregroundColor:NSColor.white]
                let size=text.size(withAttributes:attributes)
                let rect=NSRect(x:p.x-size.width/2,y:p.y+4,width:size.width,height:size.height).insetBy(dx:-2,dy:-1)
                guard [p,NSPoint(x:rect.minX,y:rect.minY),NSPoint(x:rect.maxX,y:rect.minY),NSPoint(x:rect.minX,y:rect.maxY),NSPoint(x:rect.maxX,y:rect.maxY)].allSatisfy(mapContains),
                      !occupied.contains(where: { $0.intersects(rect) }) else { continue }
                occupied.append(rect)
                NSColor.orange.setFill(); NSRect(x:p.x-2,y:p.y-2,width:4,height:4).fill()
                NSColor.black.withAlphaComponent(0.8).setFill(); rect.fill()
                text.draw(at:NSPoint(x:rect.minX+2,y:rect.minY+1),withAttributes:attributes)
            }
        }
        for mobile in mobiles where mobile.serial != player.serial && max(abs(mobile.x-player.x),abs(mobile.y-player.y))<=24 {
            let p = point(mobile)
            let color:NSColor
            if mobile.isEnemy || mobile.serial == combatTarget { color = .red }
            else { switch mobile.notoriety {
                case 1: color = .cyan
                case 2: color = .green
                case 7: color = .yellow
                default: color = .lightGray
            } }
            color.setFill(); NSBezierPath(ovalIn:NSRect(x:p.x-2,y:p.y-2,width:4,height:4)).fill()
        }
        let p = point(player)
        NSColor.black.setFill(); NSBezierPath(ovalIn:NSRect(x:p.x-4,y:p.y-4,width:8,height:8)).fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn:NSRect(x:p.x-2,y:p.y-2,width:4,height:4)).fill()
    }
    override func hitTest(_ point:NSPoint)->NSView? {
        guard let hit = super.hitTest(point), let artwork else { return nil }
        let local = convert(point,from:superview), x = Int(local.x), y = Int(local.y)
        guard x>=0,y>=0,x<artwork.width,y<artwork.height,artwork.rgba[(y*artwork.width+x)*4+3] != 0 else { return nil }
        return hit
    }
    override func mouseDown(with event:NSEvent) {
        if event.modifierFlags.contains(.shift), let player {
            let point = convert(event.locationInWindow,from:nil)
            let x:Int, y:Int
            if world {
                guard overviewRect.contains(point) else { return }
                x = Int((point.x-overviewRect.minX)/overviewRect.width*CGFloat(assets.width))
                y = Int((point.y-overviewRect.minY)/overviewRect.height*CGFloat(assets.height))
            } else {
                let px = Int(point.x), py = Int(point.y)
                guard let artwork, px>=0,py>=0,px<artwork.width,py<artwork.height else { return }
                let i = (py*artwork.width+px)*4
                guard artwork.rgba[i] == 8, artwork.rgba[i+1] == 8, artwork.rgba[i+2] == 8 else { return }
                x = player.x+Int(floor((point.x-140+point.y-140)/2))
                y = player.y+Int(floor((point.y-140-point.x+140)/2))
            }
            guard (0..<assets.width).contains(x),(0..<assets.height).contains(y) else { return }
            drag = nil; onTravel?(x,y)
        } else if event.clickCount == 2 { drag = nil; toggleMode() }
        else { drag = event.locationInWindow }
    }
    override func rightMouseDown(with event:NSEvent) { removeFromSuperview() }
    override func mouseDragged(with event:NSEvent) {
        guard let drag else { return }
        let current = event.locationInWindow
        frame.origin.x += current.x-drag.x; frame.origin.y -= current.y-drag.y
        self.drag = current
    }
    override func mouseUp(with event:NSEvent) { drag = nil }
}
