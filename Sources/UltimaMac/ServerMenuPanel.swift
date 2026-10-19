import AppKit
import UOCore

@MainActor
final class ServerMenuPanel:NSView {
    private let definition:ServerMenu, assets:ClientAssets
    private let detail = NSTextField(labelWithString:"")
    var onChoose: ((Int)->Void)?
    private var drag:NSPoint?
    override var isFlipped:Bool { true }
    init(menu:ServerMenu,assets:ClientAssets) {
        self.definition = menu; self.assets = assets
        super.init(frame:NSRect(x:320,y:120,width:menu.usesIcons ? 296 : 400,height:menu.usesIcons ? 136 : 360))
        let title = NSTextField(labelWithString:menu.title)
        title.frame = menu.usesIcons ? NSRect(x:39,y:15,width:218,height:24) : NSRect(x:20,y:16,width:360,height:42)
        title.textColor = menu.usesIcons ? .white : .black; title.lineBreakMode = .byTruncatingTail
        title.toolTip = menu.title; addSubview(title)
        let scroll = NSScrollView(frame:menu.usesIcons ? NSRect(x:40,y:42,width:217,height:49) : NSRect(x:20,y:65,width:360,height:240))
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = menu.usesIcons; scroll.hasVerticalScroller = !menu.usesIcons
        let content = MenuContent(frame:NSRect(x:0,y:0,width:menu.usesIcons ? max(217,menu.options.count*62) : 340,height:menu.usesIcons ? 49 : max(240,menu.options.count*30)))
        for option in menu.options {
            let button = MenuOptionButton(option.title.isEmpty ? "Choice \(option.index)" : option.title,fonts:assets.fonts,target:self,action:#selector(choose(_:)))
            button.tag = option.index; button.toolTip = option.title
            button.onHover = { [weak self] inside in
                self?.detail.stringValue = inside ? option.title : "Choose an item · Right-click cancels"
            }
            button.frame = menu.usesIcons ? NSRect(x:(option.index-1)*62,y:0,width:60,height:38) : NSRect(x:0,y:(option.index-1)*30,width:335,height:28)
            if menu.usesIcons, let sprite = try? assets.sprite(option.graphic+0x4000) {
                button.image = Self.image(sprite,palette:try? assets.huePalette(option.hue,art:option.graphic+0x4000))
                button.isBordered = false; button.imagePosition = .imageOnly; button.imageScaling = .scaleProportionallyDown
            }
            button.setAccessibilityLabel(option.title); content.addSubview(button)
        }
        scroll.documentView = content; addSubview(scroll)
        detail.stringValue = menu.usesIcons ? "Choose an item · Right-click cancels" : "Right-click cancels"
        detail.font = ClassicNativeFont.uiFont; detail.textColor = menu.usesIcons ? .white : .black
        detail.frame = NSRect(x:menu.usesIcons ? 40 : 20,y:menu.usesIcons ? 105 : 320,width:menu.usesIcons ? 217 : 360,height:20); addSubview(detail)
    }
    required init?(coder:NSCoder) { fatalError() }
    private static func image(_ sprite:Sprite,palette:HuePalette? = nil)->NSImage? {
        var pixels = sprite.rgba
        if let palette {
            for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3] != 0 {
                let c = palette.color(red:pixels[i],green:pixels[i+1],blue:pixels[i+2])
                pixels[i] = c.0; pixels[i+1] = c.1; pixels[i+2] = c.2
            }
        }
        guard let provider = CGDataProvider(data:Data(pixels) as CFData), let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if definition.usesIcons {
            if let s = try? assets.gumps?.sprite(0x910) { Self.image(s)?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        } else {
            for row in 0..<3 { for col in 0..<3 {
                if let s = try? assets.gumps?.sprite(0x13EC+row*3+col) {
                    let xs:[CGFloat] = [0,12,388,400], ys:[CGFloat] = [0,12,348,360]
                    Self.image(s)?.draw(in:NSRect(x:xs[col],y:ys[row],width:xs[col+1]-xs[col],height:ys[row+1]-ys[row]),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                }
            } }
        }
    }
    @objc private func choose(_ sender:NSButton) { onChoose?(sender.tag) }
    override func rightMouseDown(with event:NSEvent) { onChoose?(0) }
    override func mouseDown(with event:NSEvent) { drag = event.locationInWindow }
    override func mouseDragged(with event:NSEvent) {
        guard let drag else { return }
        frame.origin.x += event.locationInWindow.x-drag.x; frame.origin.y -= event.locationInWindow.y-drag.y; self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { drag = nil }
}
@MainActor private final class MenuContent:NSView { override var isFlipped:Bool { true } }

@MainActor private final class MenuOptionButton:ClassicButton {
    var onHover: ((Bool)->Void)?
    private var tracking:NSTrackingArea?
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        tracking = area; addTrackingArea(area); super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent) { onHover?(true) }
    override func mouseExited(with event:NSEvent) { onHover?(false) }
}
