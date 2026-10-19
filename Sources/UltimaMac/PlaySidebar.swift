import AppKit
import UOCore

/// Persistent controls outside the world viewport. No pointer events pass through to the map.
@MainActor
final class PlaySidebar: ClassicPanel {
    let skills: SkillsPanel
    private let status:ClassicLabel
    private let targetLabel:ClassicLabel
    private let title:ClassicLabel
    private let held:ClassicLabel
    private var warButton: NSButton?
    private var pickupButton:ClassicButton?
    private var pickupMode=0
    var onPickupMode:((Int)->Void)?
    var onCommand: ((Int) -> Void)?
    init(definitions: [SkillDefinition],assets:ClientAssets) {
        skills = SkillsPanel(definitions: definitions, assets:assets, docked: true)
        status=ClassicLabel("Waiting for character status...",fonts:assets.fonts)
        targetLabel=ClassicLabel("No combat target",fonts:assets.fonts)
        title=ClassicLabel("Character status",fonts:assets.fonts)
        held=ClassicLabel("",fonts:assets.fonts)
        super.init(assets:assets)
        title.frame = NSRect(x:16,y:14,width:248,height:24); addSubview(title)
        status.frame = NSRect(x:16,y:46,width:248,height:126); addSubview(status)
        for (index,title) in ["Paperdoll · P", "Backpack · B", "Use held tool · U", "Peace · A"].enumerated() {
            let button = ClassicButton(title,fonts:assets.fonts,target:self,action:#selector(command(_:)))
            button.tag = index
            if index == 3 { warButton = button }
            button.frame = NSRect(x:12,y:174+index*30,width:256,height:28)
            addSubview(button)
        }
        held.frame = NSRect(x:16,y:297,width:248,height:34); addSubview(held)
        targetLabel.frame = NSRect(x:16,y:331,width:248,height:44)
        addSubview(targetLabel)
        let pickup=ClassicButton("Gather: off",fonts:assets.fonts,target:self,action:#selector(cyclePickup))
        pickup.frame=NSRect(x:12,y:374,width:256,height:28); addSubview(pickup); pickupButton=pickup
        pickup.toolTip="Cycle: off, nearby reagents, all nearby portable ground items. Refused items are skipped. Stops on timeout or disconnect."
        let travel=ClassicButton("Travel journal",fonts:assets.fonts,target:self,action:#selector(command(_:)))
        travel.tag=4; travel.frame=NSRect(x:12,y:408,width:256,height:28); addSubview(travel)
        addSubview(skills)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layout() {
        super.layout()
        skills.frame = NSRect(x:0,y:444,width:bounds.width,height:max(80,bounds.height-444))
    }
    func updatePickupMode(_ mode:Int) {
        pickupMode=mode; pickupButton?.title=["Gather: off","Gather: reagents","Gather: all"][max(0,min(2,mode))]
        pickupButton?.needsDisplay=true
    }
    @objc private func cyclePickup() { updatePickupMode((pickupMode+1)%3); onPickupMode?(pickupMode) }
    @objc private func command(_ sender:NSButton) { onCommand?(sender.tag) }
    func updateCombatTarget(_ target:CombatTarget) {
        guard target.serial != nil else { targetLabel.stringValue = "No combat target"; return }
        let title = target.name.isEmpty ? "Combat target" : target.name
        let health = target.status?.health.map(String.init) ?? "—"
        let maximum = target.status?.maxHealth.map(String.init) ?? "—"
        targetLabel.stringValue = "\(title)\nHealth \(health) / \(maximum)"
    }
    func updateMode(war:Bool, hidden:Bool = false) {
        title.stringValue = hidden ? "Character · Hidden" : "Character status"
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
