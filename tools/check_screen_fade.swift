import AppKit
import UOCore

@main struct Check {
    final class Backdrop: NSView {
        override func draw(_ dirtyRect: NSRect) { NSColor.blue.setFill(); bounds.fill() }
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let parent = Backdrop(frame:NSRect(x:0,y:0,width:80,height:60))
        let window = NSWindow(contentRect:parent.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = parent
        let overlay = ScreenFadeOverlay()
        var time = 0.0
        overlay.now = { time }
        overlay.play(style:3,in:parent)
        precondition(overlay.superview === parent && overlay.hitTest(NSPoint(x:20,y:20)) == nil)
        precondition(!overlay.acceptsFirstResponder)
        time = 2
        overlay.tick()
        let bitmap = parent.bitmapImageRepForCachingDisplay(in:parent.bounds)!
        parent.cacheDisplay(in:parent.bounds,to:bitmap)
        let color = bitmap.colorAt(x:40,y:30)!.usingColorSpace(.deviceRGB)!
        precondition(color.redComponent > 0.99 && color.greenComponent > 0.99 && color.blueComponent > 0.99)
        time = 20
        overlay.tick()
        precondition(overlay.superview == nil,"Elapsed effects must clear even after a long blocked frame")
        overlay.play(style:0,in:parent)
        time = 20.5
        overlay.play(style:4,in:parent)
        time = 20.6
        overlay.tick()
        precondition(overlay.superview === parent,"Replacement must start its own timing")
        parent.setFrameSize(NSSize(width:100,height:90))
        precondition(overlay.frame == parent.bounds)
        overlay.cancel()
        precondition(overlay.superview == nil)
        print("Screen fade paints above the world, releases after stalls, replaces cleanly, resizes and preserves input")
    }
}
