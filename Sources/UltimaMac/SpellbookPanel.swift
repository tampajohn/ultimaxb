import AppKit
import UOCore

@MainActor
final class SpellbookPanel:NSView {
    let serial:UInt32
    private let assets:ClientAssets
    private var known:Set<Int> = []
    private var pair = 0
    private var drag:NSPoint?
    var onCast: ((Int)->Void)?
    override var isFlipped:Bool { true }
    init(serial:UInt32,assets:ClientAssets) {
        self.serial = serial; self.assets = assets
        super.init(frame:NSRect(x:310,y:70,width:406,height:229))
        toolTip = "Spellbook · Double-click a known spell to cast · Circle tabs change pages · Right-click closes · Drag blank paper to move"
        setAccessibilityLabel("Spellbook")
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ items:[ContainerItem]) { known = ClassicSpells.contents(book:serial,items:items); needsDisplay = true }
    private func sprite(_ id:Int,at point:NSPoint) {
        guard let s = try? assets.gumps?.sprite(id), let provider = CGDataProvider(data:Data(s.rgba) as CFData),
              let cg = CGImage(width:s.width,height:s.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:s.width*4,
                               space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),
                               provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return }
        NSImage(cgImage:cg,size:.zero).draw(in:NSRect(x:point.x,y:point.y,width:CGFloat(s.width),height:CGFloat(s.height)),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        sprite(0x8AC,at:.zero)
        for page in 0..<2 {
            let circle = pair*2+page, x = page == 0 ? 58 : 228
            ("Circle \(circle+1)" as NSString).draw(at:NSPoint(x:x,y:23),withAttributes:[.font:NSFont.boldSystemFont(ofSize:14),.foregroundColor:NSColor.black])
            for row in 0..<8 {
                let id = circle*8+row+1
                let text = known.contains(id) ? ClassicSpells.names[id-1] : "—"
                (text as NSString).draw(at:NSPoint(x:x,y:48+row*15),withAttributes:[.font:NSFont(name:"Times",size:13) ?? NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.black])
            }
        }
        for (i,x) in [58,93,130,164,227,260,297,332].enumerated() { sprite(0x8B1+i,at:NSPoint(x:x,y:175)) }
    }
    private func spell(at point:NSPoint)->Int? {
        let page:Int
        if (58..<199).contains(point.x) { page = 0 }
        else if (228..<370).contains(point.x) { page = 1 }
        else { return nil }
        guard (48..<168).contains(point.y) else { return nil }
        let id = (pair*2+page)*8+Int((point.y-48)/15)+1
        return known.contains(id) ? id : nil
    }
    override func mouseDown(with event:NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        if NSRect(x:0,y:95,width:25,height:30).contains(p) { removeFromSuperview(); return }
        if (175..<195).contains(p.y), let tab = [58,93,130,164,227,260,297,332].firstIndex(where: { CGFloat($0)<=p.x && p.x<CGFloat($0+19) }) {
            pair = tab/2; needsDisplay = true; return
        }
        if let id = spell(at:p) {
            if event.clickCount == 2 { onCast?(id) }
            drag = nil; return
        }
        drag = event.locationInWindow
    }
    override func mouseDragged(with event:NSEvent) {
        guard let drag else { return }
        frame.origin.x += event.locationInWindow.x-drag.x
        frame.origin.y -= event.locationInWindow.y-drag.y
        self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { drag = nil }
    override func rightMouseDown(with event:NSEvent) { removeFromSuperview() }
}
