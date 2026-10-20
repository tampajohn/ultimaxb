import AppKit
import UOCore

@MainActor final class ClassicLabel:NSView {
    private let text:ClassicText
    var stringValue:String { didSet { needsDisplay=true; setAccessibilityValue(stringValue) } }
    override var isFlipped:Bool { true }
    init(_ value:String,fonts:ClassicFonts?,color:(UInt8,UInt8,UInt8) = (230,215,170),outlined:Bool = true) {
        text=ClassicText(fonts,color:color,outlined:outlined); stringValue=value; super.init(frame:.zero)
        setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityValue(value)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func draw(_ rect:NSRect) {
        var y:CGFloat=0
        for line in stringValue.components(separatedBy:"\n") {
            var x:CGFloat=0
            for word in line.components(separatedBy:" ") {
                let size=text.size(word)
                if x+size.width>bounds.width && x>0 { x=0; y += 18 }
                text.draw(word,at:NSPoint(x:x,y:y)); x += size.width+4
            }
            y += 18
        }
    }
}

@MainActor class ClassicButton:NSButton {
    var gemBackground: NSImage?
    static let sapphireGem: NSImage? = {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource:"sapphire-button",withExtension:"png",subdirectory:"Resources")
        #else
        let url: URL? = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Resources/sapphire-button.png")
        #endif
        return url.flatMap { NSImage(contentsOf:$0) }
    }()
    private let bitmap:ClassicText
    override var isFlipped:Bool { true }
    init(_ title:String,fonts:ClassicFonts?,target:AnyObject?,action:Selector?) {
        bitmap=ClassicText(fonts); super.init(frame:.zero)
        self.title=title; self.target=target; self.action=action; isBordered=false
        setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:NSRect) {
        if let gemBackground {
            NSGraphicsContext.current?.imageInterpolation = .high
            gemBackground.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:isEnabled ? (cell?.isHighlighted == true ? 0.7 : 1) : 0.45,respectFlipped:true,hints:nil)
            let size=bitmap.size(title)
            bitmap.draw(title,at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2 + (cell?.isHighlighted == true ? 1 : 0)))
            return
        }
        if imagePosition == .imageOnly, let image {
            let sprite = cell?.isHighlighted == true ? (alternateImage ?? image) : image
            NSGraphicsContext.current?.imageInterpolation = .none
            sprite.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:isEnabled ? 1 : 0.5,respectFlipped:true,hints:nil)
            return
        }
        NSColor(calibratedRed:0.18,green:0.16,blue:0.12,alpha:cell?.isHighlighted == true ? 1 : 0.75).setFill(); bounds.fill()
        NSColor(calibratedRed:0.5,green:0.42,blue:0.25,alpha:1).setStroke()
        NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        let size=bitmap.size(title)
        bitmap.draw(title,at:NSPoint(x:max(1,(bounds.width-size.width)/2),y:max(0,(bounds.height-size.height)/2)))
        if !isEnabled { NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill() }
    }
}

@MainActor class ClassicPanel:NSView {
    let art:LoginArtwork
    override var isFlipped:Bool { true }
    init(assets:ClientAssets) {
        art=LoginArtwork(assets:assets); super.init(frame:.zero)
        wantsLayer=true; layer?.masksToBounds=true
    }
    required init?(coder:NSCoder) { fatalError() }
    // Panel backgrounds own their pointer gestures. NSView's default responder
    // forwarding otherwise turns blank UI areas into world movement/pickup.
    // Child controls still receive their own events and retain native tracking.
    override func mouseDown(with event:NSEvent) {}
    override func mouseDragged(with event:NSEvent) {}
    override func mouseUp(with event:NSEvent) {}
    override func rightMouseDown(with event:NSEvent) {}
    override func rightMouseDragged(with event:NSEvent) {}
    override func rightMouseUp(with event:NSEvent) {}
    override func scrollWheel(with event:NSEvent) {}
    override func draw(_ rect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        NSBezierPath(rect:bounds).addClip()
        // Original stone panel center tiled at its native resolution.
        if let image=art.image(0xA2C) {
            var y:CGFloat=0
            while y<bounds.height {
                var x:CGFloat=0
                while x<bounds.width {
                    image.draw(in:NSRect(x:x,y:y,width:image.size.width,height:image.size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                    x += image.size.width
                }
                y += image.size.height
            }
        }
        NSColor(calibratedRed:0.47,green:0.4,blue:0.25,alpha:1).setStroke()
        NSBezierPath(rect:bounds.insetBy(dx:1,dy:1)).stroke()
    }
}

/// Keep native menu navigation/accessibility while drawing the closed selection
/// with the same bitmap lettering as the surrounding classic panels.
@MainActor final class ClassicChoice:NSPopUpButton {
    private let bitmap:ClassicText
    override var isFlipped:Bool { true }
    init(fonts:ClassicFonts?) {
        bitmap=ClassicText(fonts)
        super.init(frame:.zero,pullsDown:false)
        isBordered=false
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:NSRect) {
        NSColor(calibratedRed:0.18,green:0.16,blue:0.12,alpha:0.9).setFill(); bounds.fill()
        NSColor(calibratedRed:0.5,green:0.42,blue:0.25,alpha:1).setStroke()
        NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:NSRect(x:5,y:0,width:max(0,bounds.width-24),height:bounds.height)).addClip()
        let value=selectedItem?.title ?? ""
        var textX:CGFloat=5
        if let swatch=selectedItem?.image {
            swatch.draw(in:NSRect(x:5,y:(bounds.height-14)/2,width:20,height:14),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            textX=30
        }
        bitmap.draw(value,at:NSPoint(x:textX,y:max(0,(bounds.height-bitmap.size(value).height)/2)))
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed:0.8,green:0.7,blue:0.45,alpha:1).setFill()
        let arrow=NSBezierPath()
        arrow.move(to:NSPoint(x:bounds.maxX-15,y:bounds.midY-2))
        arrow.line(to:NSPoint(x:bounds.maxX-5,y:bounds.midY-2))
        arrow.line(to:NSPoint(x:bounds.maxX-10,y:bounds.midY+4)); arrow.close(); arrow.fill()
        if !isEnabled { NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill() }
    }
}
