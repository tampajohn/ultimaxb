import AppKit
import UOCore

@MainActor final class ClassicLabel:NSView {
    private let text:ClassicText
    var stringValue:String { didSet { needsDisplay=true; setAccessibilityValue(stringValue) } }
    override var isFlipped:Bool { true }
    init(_ value:String,fonts:ClassicFonts?) {
        text=ClassicText(fonts); stringValue=value; super.init(frame:.zero)
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

@MainActor final class ClassicButton:NSButton {
    private let bitmap:ClassicText
    override var isFlipped:Bool { true }
    init(_ title:String,fonts:ClassicFonts?,target:AnyObject?,action:Selector?) {
        bitmap=ClassicText(fonts); super.init(frame:.zero)
        self.title=title; self.target=target; self.action=action; isBordered=false
        setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:NSRect) {
        NSColor(calibratedRed:0.18,green:0.16,blue:0.12,alpha:cell?.isHighlighted == true ? 1 : 0.75).setFill(); bounds.fill()
        NSColor(calibratedRed:0.5,green:0.42,blue:0.25,alpha:1).setStroke()
        NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        let size=bitmap.size(title)
        bitmap.draw(title,at:NSPoint(x:max(1,(bounds.width-size.width)/2),y:max(0,(bounds.height-size.height)/2)))
    }
}

@MainActor class ClassicPanel:NSView {
    let art:LoginArtwork
    override var isFlipped:Bool { true }
    init(assets:ClientAssets) { art=LoginArtwork(assets:assets); super.init(frame:.zero) }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
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
