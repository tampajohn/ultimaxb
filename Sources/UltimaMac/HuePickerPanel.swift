import AppKit
import UOCore

@MainActor final class HuePickerPanel:NSView {
    let request:HuePicker
    private let assets:ClientAssets
    private var column = 0, row = 0, shade = 1
    private var drag:NSPoint?
    private var adjustingShade = false
    private let okay = NSButton(title:"Choose color",target:nil,action:nil)
    var onChoose:((Int)->Void)?
    override var isFlipped:Bool { true }
    var selectedHue:Int { HuePicker.hue(column:column,row:row,shade:shade)! }
    init(request:HuePicker,assets:ClientAssets) {
        self.request = request; self.assets = assets
        super.init(frame:NSRect(x:350,y:180,width:260,height:180))
        if let image = gump(0x906) { frame.size = image.size }
        okay.target = self; okay.action = #selector(choose)
        okay.image = gump(0x907); okay.alternateImage = gump(0x908)
        okay.isBordered = false; okay.imagePosition = .imageOnly
        okay.frame = NSRect(x:208,y:138,width:okay.image?.size.width ?? 32,height:okay.image?.size.height ?? 24)
        okay.setAccessibilityLabel("Choose color"); addSubview(okay)
        refresh()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func gump(_ id:Int)->NSImage? {
        guard let sprite = try? assets.gumps?.sprite(id) else { return nil }
        return image(sprite)
    }
    private func image(_ sprite:Sprite,palette:HuePalette? = nil)->NSImage? {
        var pixels = sprite.rgba
        if let palette { for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3] != 0 {
            let c = palette.color(red:pixels[i],green:pixels[i+1],blue:pixels[i+2]); pixels[i] = c.0; pixels[i+1] = c.1; pixels[i+2] = c.2
        } }
        guard let provider = CGDataProvider(data:Data(pixels) as CFData),let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
    }
    private func refresh() { okay.isEnabled = (try? assets.huePalette(selectedHue)) != nil; needsDisplay = true }
    private func changeShade(at point:NSPoint) {
        shade = max(0,min(4,Int(((point.x-39)/145*4).rounded()))); refresh()
    }
    @objc private func choose() { if okay.isEnabled { onChoose?(selectedHue) } }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        gump(0x906)?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if let knob = gump(adjustingShade ? 0x846 : 0x845) {
            knob.draw(in:NSRect(x:39+CGFloat(shade)/4*(145-knob.size.width),y:142,width:knob.size.width,height:knob.size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        for y in 0..<10 { for x in 0..<20 {
            let hue = HuePicker.hue(column:x,row:y,shade:shade)!
            if let palette = try? assets.huePalette(hue) {
                let c = palette.color(red:132,green:132,blue:132)
                NSColor(srgbRed:CGFloat(c.0)/255,green:CGFloat(c.1)/255,blue:CGFloat(c.2)/255,alpha:1).setFill()
            } else { NSColor.darkGray.setFill() }
            NSRect(x:34+x*8,y:34+y*8,width:8,height:8).fill()
        } }
        NSColor.white.setStroke(); NSBezierPath(rect:NSRect(x:34+column*8,y:34+row*8,width:8,height:8).insetBy(dx:0.5,dy:0.5)).stroke()
        if let sprite = try? assets.sprite(0x4FAB),let palette = try? assets.huePalette(selectedHue,art:0x4FAB),let image = image(sprite,palette:palette) {
            image.draw(in:NSRect(origin:NSPoint(x:200,y:58),size:image.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
    }
    override func mouseDown(with event:NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        if NSRect(x:39,y:138,width:145,height:24).contains(p) {
            adjustingShade = true; drag = nil; changeShade(at:p); return
        }
        if NSRect(x:34,y:34,width:160,height:80).contains(p) {
            column = Int(p.x-34)/8; row = Int(p.y-34)/8; refresh(); drag = nil
        } else { drag = event.locationInWindow }
    }
    override func mouseDragged(with event:NSEvent) {
        if adjustingShade { changeShade(at:convert(event.locationInWindow,from:nil)); return }
        guard let drag else { return }
        frame.origin.x += event.locationInWindow.x-drag.x; frame.origin.y -= event.locationInWindow.y-drag.y; self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { drag = nil; adjustingShade = false; needsDisplay = true }
    // The server picker has no cancel response in this legacy protocol.
    override func rightMouseDown(with event:NSEvent) {}
}
