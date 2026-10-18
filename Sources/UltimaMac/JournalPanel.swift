import AppKit
import UOCore

@MainActor final class JournalPanel:NSView {
    private let scroll = NSScrollView()
    private let text = NSTextView()
    private var images:[Int:NSImage] = [:]
    private var drag:NSPoint?
    var onClose:(()->Void)?
    override var isFlipped:Bool { true }
    init(assets:ClientAssets) {
        super.init(frame:NSRect(x:300,y:60,width:300,height:430))
        for id in Array(0x820...0x823)+[0x82A,0x82B,0x82D] {
            guard let sprite = try? assets.gumps?.sprite(id),let provider = CGDataProvider(data:Data(sprite.rgba) as CFData),
                  let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { continue }
            images[id] = NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
        }
        frame.size.width = images[0x820]?.size.width ?? 300
        scroll.frame = NSRect(x:32,y:72,width:frame.width-62,height:320)
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        text.frame = NSRect(x:0,y:0,width:scroll.contentSize.width,height:scroll.contentSize.height)
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.font = .systemFont(ofSize:13); text.textColor = .black
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text; addSubview(scroll)
        let close = NSButton(title:"Close journal",target:self,action:#selector(closePanel))
        close.image = images[0x82D]; close.imagePosition = .imageOnly; close.isBordered = false
        close.frame = NSRect(x:137,y:0,width:close.image?.size.width ?? 24,height:close.image?.size.height ?? 20)
        close.setAccessibilityLabel("Close journal"); addSubview(close)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ journal:Journal) {
        let origin = scroll.contentView.bounds.origin
        let atEnd = scroll.documentVisibleRect.maxY >= text.bounds.height-2
        text.string = journal.lines.joined(separator:"\n")
        text.layoutManager?.ensureLayout(for:text.textContainer!)
        let height = max(scroll.contentSize.height,(text.layoutManager?.usedRect(for:text.textContainer!).height ?? 0)+16)
        text.setFrameSize(NSSize(width:scroll.contentSize.width,height:height))
        scroll.contentView.scroll(to:NSPoint(x:0,y:atEnd ? max(0,height-scroll.contentSize.height) : min(origin.y,max(0,height-scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        func draw(_ id:Int,_ x:CGFloat,_ y:CGFloat) {
            guard let image = images[id] else { return }
            image.draw(in:NSRect(origin:NSPoint(x:x,y:y),size:image.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        guard let top = images[0x820],let middle = images[0x821],let bottom = images[0x823] else {
            NSColor(calibratedWhite:0.85,alpha:1).setFill(); bounds.fill(); return
        }
        let offset:CGFloat = max(0,(images[0x82D]?.size.height ?? 3)-3)
        draw(0x820,0,offset)
        NSGraphicsContext.saveGraphicsState()
        NSRect(x:0,y:offset+top.size.height,width:bounds.width,height:bounds.height-offset-top.size.height-bottom.size.height).clip()
        var y = offset+top.size.height, id = 0x821
        while y < bounds.height-bottom.size.height {
            guard let image = images[id], image.size.height > 0 else { break }
            draw(id,(bounds.width-middle.size.width)/2,y); y += image.size.height; id = id == 0x821 ? 0x822 : 0x821
        }
        NSGraphicsContext.restoreGraphicsState()
        let dx = top.size.width-bottom.size.width
        draw(0x823,dx/2+dx/4,bounds.height-bottom.size.height)
        draw(0x82A,111,32); draw(0x82B,30,58); draw(0x82B,31,400)
    }
    @objc private func closePanel() { onClose?() }
    override func rightMouseDown(with event:NSEvent) { onClose?() }
    override func mouseDown(with event:NSEvent) { drag = event.locationInWindow }
    override func mouseDragged(with event:NSEvent) {
        guard let drag else { return }
        frame.origin.x += event.locationInWindow.x-drag.x; frame.origin.y -= event.locationInWindow.y-drag.y
        self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { drag = nil }
}
