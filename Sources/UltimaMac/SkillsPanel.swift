import AppKit
import UOCore

@MainActor
final class SkillsPanel: NSVisualEffectView {
    private let rows = SkillRows()
    private let definitions: [SkillDefinition]
    var onUse: ((Int) -> Void)?
    var onClose: (() -> Void)?
    init(definitions: [SkillDefinition], docked: Bool = false) {
        self.definitions = definitions
        super.init(frame: NSRect(x: 24, y: 24, width: 350, height: 520))
        material = .hudWindow; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 12
        let title = NSTextField(labelWithString: "Skills")
        title.font = .boldSystemFont(ofSize: 18)
        let close = NSButton(title: "Close", target: self, action: #selector(closePanel))
        let header = NSStackView(views: docked ? [title] : [title,close])
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 7
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.documentView = rows
        rows.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [header,scroll]); stack.orientation = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        update(SkillState())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func update(_ state: SkillState) {
        for row in rows.arrangedSubviews { rows.removeArrangedSubview(row); row.removeFromSuperview() }
        for definition in definitions.sorted(by: { $0.name < $1.name }) where state.values.isEmpty || state.values[definition.id] != nil {
            let value = state.values[definition.id].map { String(format: "%.1f", Double($0)/10) } ?? "—"
            let label = NSTextField(labelWithString: "\(definition.name)   \(value)")
            if definition.usable {
                let button = NSButton(title: "Use", target: self, action: #selector(useSkill(_:))); button.tag = definition.id
                rows.addArrangedSubview(NSStackView(views: [label,button]))
            } else { rows.addArrangedSubview(label) }
        }
    }
    @objc private func useSkill(_ sender: NSButton) { onUse?(sender.tag) }
    @objc private func closePanel() { onClose?() }
}

@MainActor
private final class SkillRows: NSStackView { override var isFlipped: Bool { true } }
