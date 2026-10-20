import AppKit
import UOCore

/// Visual-only overlay: keyboard focus and pointer hit testing stay with the game.
final class ScreenFadeOverlay: NSView {
    private var effect: ScreenFade?
    private var timer: Timer?
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    func play(style: Int, in parent: NSView) {
        effect = ScreenFade(style:style,at:now())
        frame = parent.bounds
        autoresizingMask = [.width,.height]
        parent.addSubview(self,positioned:.above,relativeTo:nil)
        timer?.invalidate()
        timer = Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer!,forMode:.common)
        needsDisplay = true
    }
    func tick() {
        guard effect?.sample(at:now()) != nil else { cancel(); return }
        needsDisplay = true
    }
    func cancel() {
        timer?.invalidate(); timer = nil
        effect = nil
        removeFromSuperview()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let sample = effect?.sample(at:now()) else { return }
        NSColor(calibratedWhite:sample.white,alpha:sample.opacity).setFill()
        bounds.fill(using:.sourceOver)
    }
}
