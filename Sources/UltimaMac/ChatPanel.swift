import AppKit
import UOCore

@MainActor
final class ChatPanel: NSView, NSTextFieldDelegate {
    private let entry = NSTextField(string: "")
    private let journal = NSTextField(wrappingLabelWithString: "")
    private(set) var history = Journal()
    var onHistory: ((Journal)->Void)?
    var onSend: ((String) -> String?)?
    var onDismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: NSRect(x: 12, y: 500, width: 540, height: 125))
        wantsLayer = true; layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.cornerRadius = 6
        journal.frame = NSRect(x: 8, y: 4, width: 524, height: 80)
        journal.textColor = .white; journal.font = .systemFont(ofSize: 12)
        entry.frame = NSRect(x: 8, y: 91, width: 524, height: 26)
        entry.placeholderString = "Say something (Enter to send, Escape to close)"
        entry.delegate = self; entry.target = self; entry.action = #selector(send)
        entry.isHidden = true
        addSubview(journal); addSubview(entry)
        isHidden = true
    }
    override func layout() {
        super.layout()
        journal.frame.size.width = max(1,bounds.width-16)
        entry.frame.size.width = max(1,bounds.width-16)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func begin() {
        let caps = KeyboardLock.clearCapsLock()
        Telemetry.shared.record("chat_caps_lock_cleared", ["status": caps.status, "enabled_after": caps.enabledAfter as Any? ?? NSNull()])
        isHidden = false; entry.isHidden = false; window?.makeFirstResponder(entry)
    }
    func append(_ text: String) {
        history.append(text); journal.stringValue = history.lines.suffix(4).joined(separator: "\n"); isHidden = false; onHistory?(history)
    }
    func reset() { history.clear(); onHistory?(history); journal.stringValue = ""; entry.stringValue = ""; entry.isHidden = true; isHidden = true }
    @objc private func send() {
        guard !entry.stringValue.isEmpty else { dismiss(); return }
        if let error = onSend?(entry.stringValue) { append(error); return }
        entry.stringValue = ""; dismiss()
    }
    private func dismiss() { entry.isHidden = true; onDismiss?() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { entry.stringValue = ""; dismiss(); return true }
        return false
    }
}
