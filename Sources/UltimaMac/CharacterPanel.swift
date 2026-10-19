import AppKit
import UOCore

@MainActor
final class CharacterPanel: NSView {
    private let avatar: AvatarView
    private let statsLabel = NSTextField(wrappingLabelWithString: "Waiting for character status…")
    private let equipmentList = NSStackView()
    var onDropEquipment: ((EquippedItem, NSPoint) -> Void)?
    var onTarget: ((UInt32)->Bool)?
    var onUseEquipment: ((UInt32) -> Void)?
    var onRemoveEquipment: ((UInt32) -> Void)?
    static func destination(in root:NSView, windowPoint:NSPoint, item:ContainerItem)->(UInt32,NSPoint)? {
        var hit = root.hitTest(root.superview?.convert(windowPoint,from:nil) ?? windowPoint)
        while let view = hit {
            if let panel = view as? CharacterPanel { return panel.dropDestination(windowPoint:windowPoint,item:item) }
            hit = view.superview
        }
        return nil
    }
    func dropDestination(windowPoint:NSPoint,item:ContainerItem)->(UInt32,NSPoint)? {
        // Buttons and status controls are not equipment drop zones.
        guard hitTest(superview?.convert(windowPoint,from:nil) ?? windowPoint) === avatar,
              let target = avatar.dropTarget(windowPoint:windowPoint,item:item) else { return nil }
        return (target,NSPoint(x:0xFFFF,y:0xFFFF))
    }
    var onClose: (() -> Void)?
    var onWarMode: (() -> Void)?
    var onSkills: (() -> Void)?
    var onBackpack: (() -> Void)?
    var onOptions: (() -> Void)?
    var onLogout: (() -> Void)?
    var onJournal: (() -> Void)?
    var onHelp: (() -> Void)?
    private let details = PaperdollDetailsView()
    private var images: [Int:NSImage] = [:]
    private var warButton: NSButton?
    private let nameLabel = NSTextField(wrappingLabelWithString:"")
    func setName(_ name:String) { nameLabel.stringValue = name }
    override var isFlipped: Bool { true }
    init(assets: ClientAssets) {
        avatar = AvatarView(assets:assets)
        super.init(frame:NSRect(x:16,y:16,width:262,height:324))
        avatar.frame = bounds; avatar.bounds = NSRect(x:0,y:0,width:262,height:324); addSubview(avatar)
        avatar.onDropEquipment = { [weak self] in self?.onDropEquipment?($0,$1) }
        avatar.onTarget = { [weak self] in self?.onTarget?($0) ?? false }
        avatar.onUseEquipment = { [weak self] in self?.onUseEquipment?($0) }
        avatar.onBackpack = { [weak self] in self?.onBackpack?() }
        avatar.onClose = { [weak self] in self?.onClose?() }
        avatar.onBackgroundDown = { [weak self] in self?.mouseDown(with:$0) }
        avatar.onBackgroundDrag = { [weak self] in self?.mouseDragged(with:$0) }
        avatar.onBackgroundUp = { [weak self] in self?.mouseUp(with:$0) }
        for (row,id,title) in [(0,0x7EF,"Help"),(1,0x7D6,"Options"),(2,0x7D9,"Log Out"),(3,0x7DC,"Journal"),(4,0x7DF,"Skills"),(5,0x7E2,"Chat"),(6,0x7E5,"Peace / War"),(7,0x7EB,"Status")] {
            guard let image = image(id) else { continue }
            let button = ClassicButton(title,fonts:avatar.assets.fonts,target:self,action:#selector(classicAction(_:)))
            button.tag = row; button.image = image; button.alternateImage = self.image(id+1)
            button.imagePosition = .imageOnly; button.isBordered = false
            button.frame = NSRect(x:185,y:44+row*27,width:Int(image.size.width),height:Int(image.size.height))
            button.setAccessibilityLabel(title); button.toolTip = title
            if row == 5 { button.isEnabled = false; button.toolTip = "This command is not implemented yet." }
            if row == 6 { warButton = button }
            avatar.addSubview(button)
        }
        nameLabel.frame = NSRect(x:30,y:262,width:180,height:36)
        nameLabel.font = ClassicNativeFont.uiFont; nameLabel.textColor = .black; nameLabel.alignment = .center
        avatar.addSubview(nameLabel)
        // Status/equipment details are revealed by the original Status button,
        // leaving only the classic paperdoll visible by default.
        details.frame = NSRect(x:10,y:30,width:242,height:280)
        details.isHidden = true; addSubview(details)
        statsLabel.font = ClassicNativeFont.uiFont
        statsLabel.frame = NSRect(x:8,y:8,width:226,height:100); details.addSubview(statsLabel)
        equipmentList.orientation = .vertical; equipmentList.alignment = .leading; equipmentList.spacing = 5
        let scroll = NSScrollView(frame:NSRect(x:8,y:112,width:226,height:120)); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.documentView = equipmentList; equipmentList.translatesAutoresizingMaskIntoConstraints = false
        equipmentList.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive = true
        details.addSubview(scroll)
        let done = ClassicButton("Back to Paperdoll",fonts:avatar.assets.fonts,target:self,action:#selector(toggleDetails))
        done.frame = NSRect(x:21,y:240,width:200,height:28); details.addSubview(done)
    }
    private func image(_ id:Int)->NSImage? {
        if let cached = images[id] { return cached }
        guard let s = try? avatar.assets.gumps?.sprite(id), let provider = CGDataProvider(data:Data(s.rgba) as CFData),
              let cg = CGImage(width:s.width,height:s.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:s.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        let image = NSImage(cgImage:cg,size:NSSize(width:s.width,height:s.height)); images[id] = image; return image
    }
    @objc private func classicAction(_ sender:NSButton) {
        switch sender.tag {
        case 0: onHelp?()
        case 1: onOptions?()
        case 2: onLogout?()
        case 3: onJournal?()
        case 4: onSkills?()
        case 6: onWarMode?()
        case 7: toggleDetails()
        default: break
        }
    }
    @objc private func toggleDetails() { details.isHidden.toggle() }
    private var dragOrigin: NSPoint?
    override func mouseDown(with event:NSEvent) { dragOrigin = superview?.convert(event.locationInWindow,from:nil) }
    override func mouseDragged(with event:NSEvent) {
        guard let parent = superview, let old = dragOrigin else { return }
        let point = parent.convert(event.locationInWindow,from:nil)
        frame.origin.x = min(max(0,frame.origin.x+point.x-old.x),max(0,parent.bounds.width-frame.width))
        frame.origin.y = min(max(0,frame.origin.y+point.y-old.y),max(0,parent.bounds.height-80))
        dragOrigin = point
    }
    override func mouseUp(with event:NSEvent) { dragOrigin = nil }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func cancelInteraction() { dragOrigin = nil; avatar.cancelInteraction() }
    func update(player: WorldMobile?, equipment: [EquippedItem]) {
        avatar.player = player; avatar.equipment = equipment; avatar.refresh()
        let war = (player?.flags ?? 0) & 0x40 != 0
        warButton?.image = image(war ? 0x7E8 : 0x7E5)
        warButton?.alternateImage = image(war ? 0x7E9 : 0x7E6)
        warButton?.toolTip = war ? "War mode — click for peace" : "Peace mode — click for war"
        for view in equipmentList.arrangedSubviews { equipmentList.removeArrangedSubview(view); view.removeFromSuperview() }
        let worn = equipment.filter { $0.owner == player?.serial }.sorted { $0.layer < $1.layer }
        for item in worn {
            let name = (try? avatar.assets.itemName(graphic: item.graphic)) ?? "Item"
            let label = NSTextField(labelWithString: name)
            if EquipmentRules.isWearable(item.layer) {
                let remove = ClassicButton("Remove",fonts:avatar.assets.fonts,target: self, action: #selector(removeEquipment(_:)))
                remove.tag = Int(item.serial)
                let use = ClassicButton("Use",fonts:avatar.assets.fonts,target: self, action: #selector(useEquipment(_:))); use.tag = Int(item.serial)
                equipmentList.addArrangedSubview(NSStackView(views: (item.layer == 1 || item.layer == 2) ? [label, use, remove] : [label, remove]))
            } else { equipmentList.addArrangedSubview(label) }
        }
        if worn.isEmpty { equipmentList.addArrangedSubview(NSTextField(labelWithString: "No equipment received.")) }
    }
    func updateStatus(_ status: CharacterStatus?) {
        guard let status else { statsLabel.stringValue = "Waiting for character status…"; return }
        func value(_ n: Int?) -> String { n.map(String.init) ?? "—" }
        statsLabel.stringValue = "Health \(value(status.health))/\(value(status.maxHealth))    Stamina \(value(status.stamina))/\(value(status.maxStamina))\n" +
            "Mana \(value(status.mana))/\(value(status.maxMana))\n" +
            "STR \(value(status.strength))    DEX \(value(status.dexterity))    INT \(value(status.intelligence))\n" +
            "Gold \(status.gold.map(String.init) ?? "—")    Armor \(value(status.armor))    Weight \(value(status.weight))"
    }
    @objc private func useEquipment(_ sender: NSButton) { onUseEquipment?(UInt32(sender.tag)) }
    @objc private func removeEquipment(_ sender: NSButton) { onRemoveEquipment?(UInt32(sender.tag)) }
    @objc private func closePanel() { onClose?() }
    @objc private func openSkills() { onSkills?() }
    @objc private func openBackpack() { onBackpack?() }
}

@MainActor
private final class AvatarView: NSView {
    let assets: ClientAssets
    var player: WorldMobile?
    var equipment: [EquippedItem] = []
    override var isFlipped: Bool { true }
    init(assets: ClientAssets) { self.assets = assets; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    var onBackpack: (() -> Void)?
    var onTarget: ((UInt32)->Bool)?
    var onUseEquipment: ((UInt32) -> Void)?
    private var layers: [Paperdoll.Layer] = []
    private var background: Sprite?
    func refresh() {
        do {
            if background == nil { background = try assets.gumps?.sprite(0x07D0) }
            if let player {
                layers = try Paperdoll.layers(assets: assets, body: player.body, hue: player.hue,
                                              owner: player.serial, equipment: equipment)
            } else { layers = [] }
        } catch { Telemetry.shared.record("character_render_error", ["error": String(describing: error)]) }
        needsDisplay = true
    }
    var onClose: (() -> Void)?
    var onBackgroundDown: ((NSEvent)->Void)?
    var onBackgroundDrag: ((NSEvent)->Void)?
    var onBackgroundUp: ((NSEvent)->Void)?
    var onDropEquipment: ((EquippedItem, NSPoint) -> Void)?
    private var draggedItem: EquippedItem?
    private var itemOrigin: NSPoint?
    private var itemPreview: ItemDragPreview?
    func dropTarget(windowPoint:NSPoint,item:ContainerItem)->UInt32? {
        let point = convert(windowPoint,from:nil)
        let x = Int(point.x)-8, y = Int(point.y)-19
        for layer in layers.reversed() {
            let sprite = layer.sprite
            guard x>=0, y>=0, x<sprite.width, y<sprite.height, sprite.rgba[(y*sprite.width+x)*4+3] != 0 else { continue }
            if let pack = layer.item, pack.layer == 21 {
                return pack.serial == item.serial ? nil : pack.serial
            }
            guard (try? assets.equipmentLayer(graphic:item.graphic)) != nil else { return nil }
            return player?.serial
        }
        return nil
    }
    func cancelInteraction() {
        itemPreview?.removeFromSuperview(); itemPreview = nil
        draggedItem = nil; itemOrigin = nil
        movingBackground = false; closing = false; consumedTarget = true
    }
    private var consumedTarget = false
    private var movingBackground = false
    private var closing = false
    private let closeArea = NSRect(x:228,y:260,width:16,height:16)
    override func mouseDown(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        itemPreview?.removeFromSuperview(); itemPreview = nil
        consumedTarget = false; movingBackground = false; closing = false
        draggedItem = nil; itemOrigin = nil
        let x = Int(point.x)-8, y = Int(point.y)-19
        if let layer = layers.reversed().first(where: {
            let sprite = $0.sprite
            return x>=0 && y>=0 && x<sprite.width && y<sprite.height && sprite.rgba[(y*sprite.width+x)*4+3] != 0
        }), let serial = layer.item?.serial ?? player?.serial, onTarget?(serial) == true {
            consumedTarget = true; return
        }
        itemOrigin = event.locationInWindow
        draggedItem = layers.reversed().first { layer in
            guard let item = layer.item, EquipmentRules.isWearable(item.layer) else { return false }
            let x = Int(point.x)-8, y = Int(point.y)-19, s = layer.sprite
            return x >= 0 && y >= 0 && x < s.width && y < s.height && s.rgba[(y*s.width+x)*4+3] != 0
        }?.item
        closing = closeArea.contains(point)
        movingBackground = !closing && !layers.contains { layer in
            guard layer.item != nil else { return false }
            let x = Int(point.x)-8, y = Int(point.y)-19, s = layer.sprite
            return x >= 0 && y >= 0 && x < s.width && y < s.height && s.rgba[(y*s.width+x)*4+3] != 0
        }
        if movingBackground { onBackgroundDown?(event) }
    }
    override func mouseDragged(with event:NSEvent) {
        if consumedTarget { return }
        if movingBackground { onBackgroundDrag?(event); return }
        guard !closing, let item = draggedItem, let origin = itemOrigin, let root = window?.contentView,
              hypot(event.locationInWindow.x-origin.x,event.locationInWindow.y-origin.y) > 4 else { return }
        if itemPreview == nil, let sprite = try? assets.sprite(item.graphic+0x4000) {
            let preview = ItemDragPreview(frame:root.bounds); preview.sprite = sprite
            root.addSubview(preview); itemPreview = preview
        }
        if let preview = itemPreview, let sprite = preview.sprite {
            let point = root.convert(event.locationInWindow,from:nil)
            preview.destination = NSRect(x:point.x,y:point.y,width:CGFloat(sprite.width*2),height:CGFloat(sprite.height*2))
            preview.needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        if consumedTarget { consumedTarget = false; return }
        onBackgroundUp?(event); movingBackground = false
        if let preview = itemPreview, let item = draggedItem {
            preview.removeFromSuperview(); itemPreview = nil; draggedItem = nil; itemOrigin = nil
            Telemetry.shared.record("paperdoll_equipment_drop",["serial":item.serial,"layer":item.layer,"x":event.locationInWindow.x,"y":event.locationInWindow.y])
            onDropEquipment?(item,event.locationInWindow); return
        }
        draggedItem = nil; itemOrigin = nil
        if closing { closing = false; if closeArea.contains(convert(event.locationInWindow,from:nil)) { onClose?() }; return }
        guard event.clickCount == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        let x = Int(p.x) - 8, y = Int(p.y) - 19
        for layer in layers.reversed() {
            let s = layer.sprite
            if x >= 0 && y >= 0 && x < s.width && y < s.height && s.rgba[(y*s.width+x)*4+3] != 0 {
                if let item = layer.item {
                    if item.layer == 21 { onBackpack?() }
                    else { onUseEquipment?(item.serial) }
                }
                return
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if let background { drawSprite(background, x: 0, y: 0) }
        for layer in layers { drawSprite(layer.sprite, x: 8, y: 19) }
    }
    private func drawSprite(_ sprite: Sprite, x: Int, y: Int) {
        let w = sprite.width, h = sprite.height
        guard let provider = CGDataProvider(data: Data(sprite.rgba) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: image, size: NSSize(width: w, height: h)).draw(
            in: NSRect(x: x, y: y, width: w, height: h), from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
private final class PaperdollDetailsView: NSView { override var isFlipped: Bool { true } }
