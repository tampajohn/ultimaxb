import AppKit
import UOCore

/// Classic quantity artwork with keyboard-accessible amount and slider controls.
@MainActor
final class StackQuantityPanel: NSView, NSTextFieldDelegate {
    private let amount = ClassicEntry(string: "1")
    private let slider: NSSlider
    private let maximum: Int
    private let background: NSImage?
    var onConfirm: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    init(maximum: Int, assets: ClientAssets) {
        self.maximum = maximum
        slider = NSSlider(value: Double(maximum), minValue: 1, maxValue: Double(maximum), target: nil, action: nil)
        background = (try? assets.gumps?.sprite(0x085C)).flatMap(Self.image)
        super.init(frame: NSRect(x: 70, y: 90, width: 320, height: 165))
        amount.stringValue = String(maximum)
        amount.frame = NSRect(x: 58, y: 84, width: 116, height: 26)
        amount.delegate = self
        amount.cell?.sendsActionOnEndEditing = false
        slider.frame = NSRect(x: 55, y: 28, width: 215, height: 30)
        slider.target = self; slider.action = #selector(slide)
        let button = ClassicButton("OK",fonts:assets.fonts,target: self, action: #selector(confirm))
        button.frame = NSRect(x: 202, y: 75, width: 68, height: 34)
        let cancel = ClassicButton("Cancel",fonts:assets.fonts,target: self, action: #selector(cancelled))
        cancel.frame = NSRect(x: 105, y: 130, width: 90, height: 26)
        let title = NSTextField(labelWithString: "Split stack — choose quantity")
        title.frame = NSRect(x: 8, y: 0, width: 300, height: 22)
        title.font = ClassicNativeFont.uiFont
        title.textColor = .white; title.drawsBackground = true; title.backgroundColor = .black
        addSubview(title)
        addSubview(slider); addSubview(amount); addSubview(button); addSubview(cancel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(amount); amount.selectText(nil) }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let background {
            background.draw(in: NSRect(x: 0, y: 0, width: 320, height: 126), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else { NSColor.darkGray.setFill(); bounds.fill() }
    }
    @objc private func slide() { amount.integerValue = Int(slider.doubleValue.rounded()) }
    func controlTextDidChange(_ notification: Notification) {
        if let value = Int(amount.stringValue) { slider.integerValue = min(maximum, max(1, value)) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { confirm(); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelled(); return true }
        return false
    }
    @objc private func confirm() {
        guard let value = Int(amount.stringValue), (1...maximum).contains(value) else { NSSound.beep(); return }
        onConfirm?(value)
    }
    @objc private func cancelled() { onCancel?() }
    private static func image(_ sprite: Sprite) -> NSImage? {
        guard let provider = CGDataProvider(data: Data(sprite.rgba) as CFData),
              let image = CGImage(width: sprite.width, height: sprite.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: sprite.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: sprite.width, height: sprite.height))
    }
}
