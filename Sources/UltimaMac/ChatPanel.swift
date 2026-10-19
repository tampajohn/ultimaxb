import AppKit
import UOCore

@MainActor
final class ChatPanel: NSView, NSTextFieldDelegate {
    private let entry = ClassicEntry(string: "")
    private let modeLabel:ClassicLabel
    private let journal:ChatHistoryPreview
    private let historyButton:ClassicButton
    var onHistoryRequested: ((NSEvent?) -> Void)?
    private(set) var history = Journal()
    var onHistory: ((Journal)->Void)?
    var onSend: ((String) -> String?)?
    var onDismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    init(assets: ClientAssets) {
        modeLabel=ClassicLabel("Say",fonts:assets.fonts)
        journal=ChatHistoryPreview(fonts:assets.fonts)
        historyButton=ClassicButton("Journal · J",fonts:assets.fonts,target:nil,action:nil)
        super.init(frame: NSRect(x: 12, y: 500, width: 540, height: 125))
        wantsLayer = true; layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.masksToBounds = true
        historyButton.target = self; historyButton.action = #selector(openHistory)
        historyButton.setAccessibilityLabel("Open chat history journal")
        historyButton.toolTip = "Open the journal (J). Scroll over recent messages to browse history."
        historyButton.frame = NSRect(x: 428, y: 2, width: 104, height: 24)
        addSubview(historyButton)
        journal.onScroll = { [weak self] event in self?.onHistoryRequested?(event) }
        journal.frame = NSRect(x: 8, y: 4, width: 412, height: 70)
        entry.frame = NSRect(x: 8, y: 91, width: 524, height: 26)
        modeLabel.frame = NSRect(x:8,y:75,width:524,height:16)
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
@MainActor private final class ChatHistoryPreview: NSView {
    private let text:ClassicText
    var stringValue="" { didSet { needsDisplay=true; setAccessibilityValue(stringValue) } }
    override var isFlipped:Bool { true }
    init(fonts:ClassicFonts?) {
        text=ClassicText(fonts,font:3,color:(255,255,255)); super.init(frame:.zero)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ rect:NSRect) {
        NSBezierPath(rect:bounds).addClip()
        let lines=text.lines(stringValue,width:bounds.width-2)
        let lineHeight=max(18,lines.map { text.size($0).height+2 }.max() ?? 18)
        let visible=lines.suffix(max(1,Int(bounds.height/lineHeight)))
        for (index,line) in visible.enumerated() { text.draw(line,at:NSPoint(x:1,y:CGFloat(index)*lineHeight)) }
    }
    var onScroll: ((NSEvent) -> Void)?
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
}
