import AppKit
import UOCore

/// Sprite IDs verified against CrossUO GumpDrag, GUIHTMLGump and GumpBaseScroll.
/// AppKit continues to own tracking, keyboard input and accessibility.
@MainActor enum ClassicControlArt {
    private static var art:LoginArtwork?
    static func install(_ assets:ClientAssets) { if art == nil { art=LoginArtwork(assets:assets) } }
    static func image(_ id:Int)->NSImage? { art?.image(id) }
    static func draw(_ id:Int,in rect:NSRect,flipped:Bool) {
        NSGraphicsContext.current?.imageInterpolation = .none
        image(id)?.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:flipped,hints:nil)
    }
    static func apply(to scroll:NSScrollView) {
        guard art != nil else { return }
        // Legacy scrollers reserve space instead of floating modern translucent
        // controls over parchment text. Each replacement is performed once.
        scroll.scrollerStyle = .legacy
        if scroll.hasVerticalScroller, !(scroll.verticalScroller is ClassicScroller) {
            scroll.verticalScroller=ClassicScroller(frame:NSRect(x:0,y:0,width:16,height:100))
        }
        if scroll.hasHorizontalScroller, !(scroll.horizontalScroller is ClassicScroller) {
            scroll.horizontalScroller=ClassicScroller(frame:NSRect(x:0,y:0,width:100,height:16))
        }
    }
}
@MainActor final class ClassicScroller:NSScroller {
    override class var isCompatibleWithOverlayScrollers:Bool { false }
    override func drawKnobSlot(in slotRect:NSRect,highlight flag:Bool) {
        NSColor(calibratedRed:0.2,green:0.17,blue:0.11,alpha:1).setFill(); slotRect.fill()
        NSColor(calibratedRed:0.5,green:0.4,blue:0.2,alpha:1).setStroke()
        NSBezierPath(rect:slotRect.insetBy(dx:0.5,dy:0.5)).stroke()
    }
    override func drawKnob() {
        let rect=rect(for:.knob)
        guard !rect.isEmpty else { return }
        let id = bounds.height>bounds.width ? 0x1F : 0xD8
        guard let image=ClassicControlArt.image(id) else { return }
        let scale=min(rect.width/image.size.width,rect.height/image.size.height)
        let size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
        ClassicControlArt.draw(id,in:NSRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height),flipped:isFlipped)
    }
}
@MainActor final class ClassicSliderCell:NSSliderCell {
    override func drawBar(inside rect:NSRect,flipped:Bool) {
        let track=NSRect(x:rect.minX,y:rect.midY-2,width:rect.width,height:4)
        NSColor(calibratedRed:0.18,green:0.12,blue:0.07,alpha:1).setFill(); track.fill()
        NSColor(calibratedRed:0.5,green:0.4,blue:0.2,alpha:1).setStroke()
        NSBezierPath(rect:track).stroke()
    }
    override func drawKnob(_ rect:NSRect) {
        ClassicControlArt.draw(isHighlighted ? 0x846 : 0x845,in:rect,flipped:controlView?.isFlipped ?? false)
    }
}
@MainActor final class ClassicSlider:NSSlider {
    override class var cellClass:AnyClass? { get { ClassicSliderCell.self } set {} }
}
