import AppKit
import UOCore

@MainActor final class JournalPanel:NSView {
    private let scroll = NSScrollView()
    private let text: JournalText
    private var images:[Int:NSImage] = [:]
    private var drag:NSPoint?
    var onClose:(()->Void)?
    override var isFlipped:Bool { true }
    init(assets:ClientAssets) {
        text = JournalText(fonts:assets.fonts)
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
        text.setContents(journal.lines.joined(separator:"\n"),width:scroll.contentSize.width,minimumHeight:scroll.contentSize.height)
        let height = text.bounds.height
        scroll.contentView.scroll(to:NSPoint(x:0,y:atEnd ? max(0,height-scroll.contentSize.height) : min(origin.y,max(0,height-scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func scrollHistory(with event: NSEvent) {
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 16)
        let maximum = max(0, text.bounds.height - scroll.contentSize.height)
        let y = min(maximum, max(0, scroll.contentView.bounds.minY - delta))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    override func scrollWheel(with event: NSEvent) { scrollHistory(with: event) }
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

/// Original bitmap letterforms, with native fallback for unsupported characters.
@MainActor final class JournalText: NSView {
    private struct Letter {
        let image:NSImage?
        let fallback:String?
        let width:CGFloat, height:CGFloat, offset:CGFloat
    }
    private let fonts:ClassicFonts?
    private var cache:[Unicode.Scalar:Letter] = [:]
    private var placements:[(Letter,NSPoint)] = []
    private(set) var string = ""
    private let fallbackAttributes:[NSAttributedString.Key:Any] = [.font:ClassicNativeFont.uiFont,.foregroundColor:NSColor.black]
    private var lineHeight:CGFloat = 18
    override var isFlipped:Bool { true }
    init(fonts:ClassicFonts?) {
        self.fonts = fonts
        super.init(frame:.zero)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        if let fonts {
            for code in UInt32(32)...255 {
                if let scalar = Unicode.Scalar(code),let glyph = try? fonts.glyph(scalar,font:min(9,fonts.count-1)) {
                    lineHeight = max(lineHeight,CGFloat(glyph.sprite.height+glyph.offsetY+2))
                }
            }
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    private func letter(_ scalar:Unicode.Scalar)->Letter {
        if let existing = cache[scalar] { return existing }
        let result:Letter
        if let fonts,let glyph = try? fonts.glyph(scalar,font:min(9,fonts.count-1)),
           (glyph.sprite.width > 0 && glyph.sprite.height > 0) || scalar == " " {
            let sprite = glyph.sprite
            var pixels = sprite.rgba
            for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3] != 0 {
                pixels[i] = 35; pixels[i+1] = 24; pixels[i+2] = 15
            }
            var image:NSImage?
            if sprite.width > 0,sprite.height > 0,let provider = CGDataProvider(data:Data(pixels) as CFData),
               let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,
                               space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),
                               provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) {
                image = NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
            }
            result = Letter(image:image,fallback:nil,width:CGFloat(max(scalar == " " ? 4 : 1,sprite.width)),height:CGFloat(sprite.height),offset:CGFloat(glyph.offsetY))
        } else {
            let text = String(scalar)
            result = Letter(image:nil,fallback:text,width:(text as NSString).size(withAttributes:fallbackAttributes).width,height:16,offset:0)
        }
        // Latin-1 cache is fixed-size; arbitrary chat Unicode does not grow it.
        if scalar.value <= 255 { cache[scalar] = result }
        return result
    }
    func setContents(_ value:String,width:CGFloat,minimumHeight:CGFloat) {
        string = value; placements.removeAll(keepingCapacity:true)
        setAccessibilityValue(value)
        let left:CGFloat = 5, right = max(6,width-5)
        var x = left, y:CGFloat = 4
        for (index,line) in value.components(separatedBy:"\n").enumerated() {
            if index > 0 { y += lineHeight; x = left }
            for (wordIndex,word) in line.components(separatedBy:" ").enumerated() {
                let letters = word.unicodeScalars.map { letter($0) }
                let space = letter(" ")
                let wordWidth = letters.reduce(CGFloat(0)) { $0+$1.width }
                if wordIndex > 0 {
                    if x+space.width+wordWidth > right && x > left { y += lineHeight; x = left }
                    else { x += space.width }
                }
                for glyph in letters {
                    if x+glyph.width > right && x > left { y += lineHeight; x = left }
                    placements.append((glyph,NSPoint(x:x,y:y+glyph.offset)))
                    x += glyph.width
                }
            }
        }
        setFrameSize(NSSize(width:width,height:max(minimumHeight,y+lineHeight+8)))
        needsDisplay = true
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        for (letter,point) in placements {
            let rect = NSRect(origin:point,size:NSSize(width:letter.width,height:letter.height))
            guard rect.intersects(dirtyRect) else { continue }
            if let image = letter.image {
                image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            } else if let fallback = letter.fallback {
                (fallback as NSString).draw(at:point,withAttributes:fallbackAttributes)
            }
        }
    }
}
