import AppKit
import UOCore

@MainActor
final class ChatPanel: NSView, NSTextFieldDelegate {
    private let entry = NSTextField(string: "")
    private let modeLabel = NSTextField(labelWithString:"Say")
    private let journal = ChatHistoryPreview(wrappingLabelWithString: "")
    private let historyButton = NSButton(title: "Journal · J", target: nil, action: nil)
    var onHistoryRequested: ((NSEvent?) -> Void)?
    private(set) var history = Journal()
    var onHistory: ((Journal)->Void)?
    var onSend: ((String) -> String?)?
    var onDismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    init(assets: ClientAssets) {
        super.init(frame: NSRect(x: 12, y: 500, width: 540, height: 125))
        wantsLayer = true; layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.cornerRadius = 6
        historyButton.target = self; historyButton.action = #selector(openHistory)
        historyButton.setAccessibilityLabel("Open chat history journal")
        historyButton.toolTip = "Open the journal (J). Scroll over recent messages to browse history."
        if let sprite = try? assets.gumps?.sprite(0x82A),
           let provider = CGDataProvider(data: Data(sprite.rgba) as CFData),
           let image = CGImage(width: sprite.width, height: sprite.height, bitsPerComponent: 8, bitsPerPixel: 32,
               bytesPerRow: sprite.width * 4, space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
               decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            historyButton.image = NSImage(cgImage: image, size: NSSize(width: sprite.width, height: sprite.height))
            historyButton.imagePosition = .imageOnly
            historyButton.isBordered = false
        }
        historyButton.frame = NSRect(x: 428, y: 2, width: 104, height: 24)
        addSubview(historyButton)
        journal.onScroll = { [weak self] event in self?.onHistoryRequested?(event) }
        journal.frame = NSRect(x: 8, y: 4, width: 412, height: 70)
        journal.textColor = .white; journal.font = .systemFont(ofSize: 12)
        entry.frame = NSRect(x: 8, y: 91, width: 524, height: 26)
        modeLabel.frame = NSRect(x:8,y:75,width:524,height:16)
        modeLabel.font = .systemFont(ofSize:11); modeLabel.textColor = .white
        modeLabel.isHidden = true
        entry.placeholderString = "Say · ; whisper · ! yell · : emote (prefix + space)"
        entry.toolTip = "Enter sends; Escape cancels. Start with ; space to whisper, ! space to yell, or : space to emote."
        entry.delegate = self; entry.target = self; entry.action = #selector(send)
        entry.isHidden = true
        addSubview(journal); addSubview(modeLabel); addSubview(entry)
        isHidden = true
    }
    override func layout() {
        super.layout()
        journal.frame.size.width = max(1,bounds.width-128)
        historyButton.frame.origin.x = max(8,bounds.width-112)
        modeLabel.frame.size.width = max(1,bounds.width-16)
        entry.frame.size.width = max(1,bounds.width-16)
    }
    @objc private func openHistory() { onHistoryRequested?(nil) }
    override func scrollWheel(with event: NSEvent) { onHistoryRequested?(event) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func begin() {
        let caps = KeyboardLock.clearCapsLock()
        Telemetry.shared.record("chat_caps_lock_cleared", ["status": caps.status, "enabled_after": caps.enabledAfter as Any? ?? NSNull()])
        modeLabel.stringValue = SpeechPackets.mode(for:entry.stringValue).label; modeLabel.isHidden = false
        isHidden = false; entry.isHidden = false; window?.makeFirstResponder(entry)
    }
    func append(_ text: String) {
        history.append(text); journal.stringValue = history.lines.suffix(4).joined(separator: "\n"); isHidden = false; onHistory?(history)
    }
    func reset() { history.clear(); onHistory?(history); journal.stringValue = ""; entry.stringValue = ""; entry.isHidden = true; modeLabel.isHidden = true; isHidden = true }
    @objc private func send() {
        guard !entry.stringValue.isEmpty else { dismiss(); return }
        if let error = onSend?(entry.stringValue) { append(error); return }
        entry.stringValue = ""; dismiss()
    }
    func controlTextDidChange(_ notification:Notification) { modeLabel.stringValue = SpeechPackets.mode(for:entry.stringValue).label }
    private func dismiss() { entry.isHidden = true; modeLabel.isHidden = true; onDismiss?() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { entry.stringValue = ""; dismiss(); return true }
        return false
    }
}

/// Route history scrolling to the original journal instead of panning the world.
@MainActor private final class ChatHistoryPreview: NSTextField {
    var onScroll: ((NSEvent) -> Void)?
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
}
