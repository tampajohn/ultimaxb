import AppKit
import UOCore

/// Persistent controls outside the world viewport. No pointer events pass through to the map.
@MainActor
final class PlaySidebar: NSView {
    let skills: SkillsPanel
    private let status = NSTextField(wrappingLabelWithString: "Waiting for character status…")
    private let targetLabel = NSTextField(wrappingLabelWithString:"No combat target")
    private let held = NSTextField(wrappingLabelWithString: "")
    private var warButton: NSButton?
    var onCommand: ((Int) -> Void)?
    override var isFlipped: Bool { true }
    init(definitions: [SkillDefinition]) {
        skills = SkillsPanel(definitions: definitions, docked: true)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        let title = NSTextField(labelWithString: "Character status")
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x:16,y:14,width:248,height:24); addSubview(title)
        status.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        status.textColor = .white
        status.frame = NSRect(x:16,y:46,width:248,height:126); addSubview(status)
        for (index,title) in ["Paperdoll · P", "Backpack · B", "Use held tool · U", "Peace · A"].enumerated() {
            let button = NSButton(title:title,target:self,action:#selector(command(_:)))
            button.tag = index
            if index == 3 { warButton = button }
            button.frame = NSRect(x:12,y:174+index*30,width:256,height:28)
            addSubview(button)
        }
        held.font = .systemFont(ofSize:11); held.textColor = .secondaryLabelColor
        held.frame = NSRect(x:16,y:297,width:248,height:34); addSubview(held)
        targetLabel.font = .systemFont(ofSize:12)
        targetLabel.frame = NSRect(x:16,y:331,width:248,height:44)
        addSubview(targetLabel)
        addSubview(skills)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layout() {
        super.layout()
        skills.frame = NSRect(x:0,y:381,width:bounds.width,height:max(80,bounds.height-381))
    }
    @objc private func command(_ sender:NSButton) { onCommand?(sender.tag) }
    func updateCombatTarget(_ target:CombatTarget) {
        guard target.serial != nil else { targetLabel.stringValue = "No combat target"; return }
        let title = target.name.isEmpty ? "Combat target" : target.name
        let health = target.status?.health.map(String.init) ?? "—"
        let maximum = target.status?.maxHealth.map(String.init) ?? "—"
        targetLabel.stringValue = "\(title)\nHealth \(health) / \(maximum)"
    }
    func updateMode(war:Bool) {
        warButton?.title = war ? "War · A" : "Peace · A"
        warButton?.toolTip = "Toggle peace/war mode. In war mode, double-click a mobile to attack."
    }
    func updateStatus(_ value: CharacterStatus?) {
        guard let value else { status.stringValue = "Waiting for character status…"; return }
        func n(_ v:Int?) -> String { v.map(String.init) ?? "—" }
        status.stringValue = "Health   \(n(value.health)) / \(n(value.maxHealth))\nStamina  \(n(value.stamina)) / \(n(value.maxStamina))\nMana     \(n(value.mana)) / \(n(value.maxMana))\n\nSTR \(n(value.strength))  DEX \(n(value.dexterity))  INT \(n(value.intelligence))\nArmor \(n(value.armor))   Weight \(n(value.weight))\nGold \(value.gold.map(String.init) ?? "—")"
    }
    func updateEquipment(_ items:[EquippedItem], player:UInt32?, assets:ClientAssets) {
        let hands = items.filter { $0.owner == player && ($0.layer == 1 || $0.layer == 2) }.sorted { $0.layer < $1.layer }
        held.stringValue = hands.isEmpty ? "No held items" : hands.map { (try? assets.itemName(graphic:$0.graphic)) ?? "Held item" }.joined(separator:" · ")
    }
}
