import Foundation

struct PacketReader {
    let bytes: [UInt8]
    var offset: Int
    init(_ data: Data, offset: Int = 0) { bytes = Array(data); self.offset = offset }
    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw LoginProtocolError.malformedPacket }
        defer { offset += 1 }
        return bytes[offset]
    }
    mutating func word() throws -> UInt16 { UInt16(try byte()) << 8 | UInt16(try byte()) }
    mutating func dword() throws -> UInt32 { UInt32(try word()) << 16 | UInt32(try word()) }
}

public struct GroundItem: Equatable, Sendable {
    public let serial: UInt32
    public let graphic: Int
    public let amount: Int
    public let x: Int, y: Int, z: Int
    public let direction: UInt8
    public let hue: Int
    public let flags: UInt8
    public var corpseEquipment:[EquippedItem] = []

    public static func decode(_ packet: Data) throws -> GroundItem {
        var r = PacketReader(packet)
        guard try r.byte() == 0x1A, Int(try r.word()) == packet.count else {
            throw LoginProtocolError.malformedPacket
        }
        let serial = try r.dword()
        let graphic = try r.word()
        let increment = graphic & 0x8000 != 0 ? Int(try r.byte()) : 0
        let amount = serial & 0x80000000 != 0 ? Int(try r.word()) : 1
        let x = try r.word(), y = try r.word()
        let direction = x & 0x8000 != 0 ? try r.byte() : 0
        let z = Int(Int8(bitPattern: try r.byte()))
        let hue = y & 0x8000 != 0 ? Int(try r.word()) : 0
        let flags = y & 0x4000 != 0 ? try r.byte() : 0
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        return GroundItem(serial: serial & 0x7fffffff, graphic: Int(graphic & 0x7fff) + increment,
                          amount: amount, x: Int(x & 0x7fff), y: Int(y & 0x3fff), z: z,
                          direction: direction, hue: hue, flags: flags)
    }
}

/// Ground objects and mobile bodies. Container/equipment messages remove objects from the
/// ground layer; their full UI models and multi-component expansion come later.
public struct WorldState {
    public private(set) var mobiles: [UInt32: WorldMobile] = [:]
    public private(set) var items: [UInt32: GroundItem] = [:]
    public private(set) var equipment: [UInt32: EquippedItem] = [:]
    public private(set) var containerItems: [UInt32: ContainerItem] = [:]
    private var corpseLayers:[UInt32:[UInt8:UInt32]] = [:]
    public private(set) var openContainer: OpenContainer?
    // An empty 0x3C has no parent serial. Its preceding open/corpse-equipment
    // packet supplies the owner; the last UI container may be unrelated.
    private var contentsContext: UInt32?
    public init() {}
    @discardableResult public mutating func apply(_ packet: Data) throws -> Bool {
        guard let opcode = packet.first else { throw LoginProtocolError.malformedPacket }
        switch opcode {
        case 0x89:
            let contents = try CorpseEquipment.decode(packet)
            contentsContext = contents.serial
            guard corpseLayers[contents.serial] != contents.layers else { return false }
            guard corpseLayers[contents.serial] != nil || corpseLayers.count < 4096 else { throw LoginProtocolError.bufferLimit }
            corpseLayers[contents.serial] = contents.layers
            return true
        case 0x1B, 0x20, 0x77, 0x78:
            var mobile = try WorldMobile.decode(packet)
            if opcode == 0x20, let previous = mobiles[mobile.serial] { mobile = mobile.withNotoriety(previous.notoriety) }
            var equipmentChanged = false
            if opcode == 0x78 {
                let incoming = try EquippedItem.list(from: packet)
                let previous = equipment
                equipment = equipment.filter { $0.value.owner != mobile.serial }
                for item in incoming { equip(item) }
                equipmentChanged = previous != equipment
            }
            guard mobiles[mobile.serial] != mobile else { return equipmentChanged }
            guard mobiles[mobile.serial] != nil || mobiles.count < 4096 else { throw LoginProtocolError.bufferLimit }
            mobiles[mobile.serial] = mobile
            return true
        case 0x2E:
            let item = try EquippedItem.decode(packet)
            guard equipment[item.serial] != item || items[item.serial] != nil else { return false }
            guard equipment[item.serial] != nil || equipment.count < 65_536 else { throw LoginProtocolError.bufferLimit }
            equip(item)
            containerItems.removeValue(forKey: item.serial)
            items.removeValue(forKey: item.serial)
            return true
        case 0x1A:
            let item = try GroundItem.decode(packet)
            guard item.serial & 0x40000000 != 0 else { return false } // mobiles use animation art
            guard items[item.serial] != item else { return false }
            guard items[item.serial] != nil || items.count < 65_536 else { throw LoginProtocolError.bufferLimit }
            equipment.removeValue(forKey: item.serial)
            containerItems.removeValue(forKey: item.serial)
            items[item.serial] = item
            return true
        case 0xAF:
            let death = try MobileDeath.decode(packet)
            let removed = mobiles.removeValue(forKey:death.serial) != nil
            let oldEquipment = equipment.count
            equipment = equipment.filter { $0.value.owner != death.serial }
            return removed || oldEquipment != equipment.count
        case 0x1D:
            guard packet.count == 5 else { throw LoginProtocolError.malformedPacket }
            var r = PacketReader(packet, offset: 1)
            let serial = try r.dword()
            corpseLayers.removeValue(forKey:serial)
            let removedItem = items.removeValue(forKey: serial) != nil
            let removedMobile = opcode == 0x1D ? mobiles.removeValue(forKey: serial) != nil : false
            let oldEquipment = equipment.count
            equipment = equipment.filter { $0.key != serial && !(opcode == 0x1D && $0.value.owner == serial) }
            let removedContainerItem = containerItems.removeValue(forKey: serial) != nil
            return removedItem || removedMobile || oldEquipment != equipment.count || removedContainerItem
        case 0x24:
            openContainer = try OpenContainer.decode(packet)
            contentsContext = openContainer?.serial
            return true
        case 0x25, 0x3C:
            let incoming = try ContainerItem.decode(packet)
            var updated = containerItems
            if opcode == 0x3C {
                let parents = Set(incoming.map(\.container))
                let replaced = incoming.isEmpty ? Set(contentsContext.map { [$0] } ?? []) : parents
                updated = updated.filter { !replaced.contains($0.value.container) }
            }
            for item in incoming { updated[item.serial] = item }
            guard updated.count <= 65_536 else { throw LoginProtocolError.bufferLimit }
            let changed = updated != containerItems || incoming.contains { items[$0.serial] != nil || equipment[$0.serial] != nil }
            for item in incoming {
                items.removeValue(forKey: item.serial)
                equipment.removeValue(forKey: item.serial)
            }
            containerItems = updated
            if opcode == 0x3C { contentsContext = nil }
            return changed
        default: return false
        }
    }
    /// Keep live scenery around the player, with a margin beyond the classic
    /// server visibility radius. Inventory is a separate lifetime/domain.
    @discardableResult public mutating func pruneWorld(around playerSerial: UInt32, radius: Int = 32) -> Int {
        guard radius >= 0, let player = mobiles[playerSerial] else { return 0 }
        func nearby(_ x: Int, _ y: Int) -> Bool {
            abs(x - player.x) <= radius && abs(y - player.y) <= radius
        }
        let previous = items.count + mobiles.count + equipment.count
        items = items.filter { nearby($0.value.x, $0.value.y) }
        let expiredCorpses = Set(corpseLayers.keys.filter { items[$0] == nil })
        corpseLayers = corpseLayers.filter { !expiredCorpses.contains($0.key) }
        containerItems = containerItems.filter { !expiredCorpses.contains($0.value.container) }
        let removed = Set(mobiles.values.filter { $0.serial != playerSerial && !nearby($0.x, $0.y) }.map(\.serial))
        mobiles = mobiles.filter { !removed.contains($0.key) }
        equipment = equipment.filter { !removed.contains($0.value.owner) }
        return previous - items.count - mobiles.count - equipment.count
    }
    private mutating func equip(_ item: EquippedItem) {
        equipment = equipment.filter { $0.key != item.serial && !($0.value.owner == item.owner && $0.value.layer == item.layer) }
        containerItems.removeValue(forKey: item.serial)
        equipment[item.serial] = item
    }
    public mutating func setPlayerPosition(_ mobile: WorldMobile) {
        guard mobiles[mobile.serial] != nil else { return }
        mobiles[mobile.serial] = mobile
    }
    public var groundObjects:[GroundItem] {
        items.values.sorted { $0.serial < $1.serial }.map { item in
            var result = item
            if item.graphic == 0x2006 {
                result.corpseEquipment = (corpseLayers[item.serial] ?? [:]).compactMap { layer,serial in
                    guard let equipment = containerItems[serial], equipment.container == item.serial else { return nil }
                    return EquippedItem(serial:serial,graphic:equipment.graphic,layer:layer,owner:item.serial,hue:equipment.hue)
                }.sorted { $0.layer < $1.layer }
            }
            return result
        }
    }
    public var groundTiles: [WorldTile] {
        groundObjects.compactMap { item in
            guard item.graphic < 0x4000, item.flags & 0x80 == 0 else { return nil }
            var tile = WorldTile(x: item.x, y: item.y, z: item.z, art: item.graphic + 0x4000, hue: item.hue,
                             lightID: Int(item.direction), corpseBody:item.graphic == 0x2006 ? item.amount : nil,corpseDirection:item.direction,corpseEquipment:item.corpseEquipment)
            tile.isDynamic = true
            tile.sourceSerial = item.serial
            return tile
        }
    }
}
