import AppKit
import UOCore

/// Casting always goes through the active book validation.
@MainActor
final class SpellShortcut:NSView {
    let spell:Int
    private let image:NSImage?
    private var drag:NSPoint?
    var onCast:(()->Void)?
    var onClose:(()->Void)?
    var onMoved:(()->Void)?
    override var isFlipped:Bool { true }
    init(spell:Int,assets:ClientAssets) {
        self.spell = spell
        if let detail = ClassicSpells.detail(id:spell),let sprite = try? assets.gumps?.sprite(detail.icon),
           let provider = CGDataProvider(data:Data(sprite.rgba) as CFData),
           let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,
                            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),
                            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) {
            image = NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
        } else { image = nil }
        super.init(frame:NSRect(origin:.zero,size:image?.size ?? NSSize(width:44,height:44)))
        let name = (1...64).contains(spell) ? ClassicSpells.names[spell-1] : "Spell"
        toolTip = "\(name) · Double-click to cast · Drag to move · Right-click to remove"
        setAccessibilityLabel(name)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let image { image.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        else { NSColor.darkGray.setFill(); bounds.fill() }
    }
    func place(at point:NSPoint,in parent:NSView) {
        frame.origin = NSPoint(x:max(0,min(parent.bounds.width-frame.width,point.x-frame.width/2)),
                               y:max(0,min(parent.bounds.height-frame.height,point.y-frame.height/2)))
    }
    override func mouseDown(with event:NSEvent) {
        drag = event.locationInWindow
        if event.clickCount == 2 { drag = nil; onCast?() }
    }
    override func mouseDragged(with event:NSEvent) {
        guard let drag,let parent = superview else { return }
        let from = parent.convert(drag,from:nil),to = parent.convert(event.locationInWindow,from:nil)
        place(at:NSPoint(x:frame.midX+to.x-from.x,y:frame.midY+to.y-from.y),in:parent)
        self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { if drag != nil { onMoved?() }; drag = nil }
    override func rightMouseDown(with event:NSEvent) { onClose?(); removeFromSuperview() }
}
