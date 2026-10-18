import Foundation

public struct EquippedItem: Equatable, Sendable {
    public let serial: UInt32
    public let graphic: Int
    public let layer: UInt8
    public let owner: UInt32
    public let hue: Int

    public init(serial: UInt32, graphic: Int, layer: UInt8, owner: UInt32, hue: Int = 0) {
        self.serial = serial; self.graphic = graphic; self.layer = layer
        self.owner = owner; self.hue = hue
    }
    public static func decode(_ packet: Data) throws -> EquippedItem {
        guard packet.first == 0x2E, packet.count == 15 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet, offset: 1)
        let serial = try r.dword(), graphic = Int(try r.word())
        _ = try r.byte() // Historical OUO stackable/reserved byte.
        let layer = try r.byte(), owner = try r.dword()
        return EquippedItem(serial: serial, graphic: graphic, layer: layer, owner: owner, hue: Int(try r.word()))
    }
    public static func list(from packet: Data) throws -> [EquippedItem] {
        _ = try WorldMobile.decode(packet) // Validate the complete mobile and terminated list.
        guard packet.first == 0x78 else { throw LoginProtocolError.malformedPacket }
        var header = PacketReader(packet, offset: 3)
        let owner = try header.dword()
        var r = PacketReader(packet, offset: 19)
        var items: [EquippedItem] = []
        while true {
            let serial = try r.dword()
            if serial == 0 { break }
            let graphic = try r.word(), layer = try r.byte()
            let hue = graphic & 0x8000 != 0 ? Int(try r.word()) : 0
            items.append(EquippedItem(serial: serial, graphic: Int(graphic & 0x7FFF), layer: layer, owner: owner, hue: hue))
        }
        return items
    }
}

// Initial classic equipment order, adapted from ClassicUO PaperdollOrder.cs.
// See LICENSES/ClassicUO.txt. Special armor coverage rules remain to be added.
public enum EquipmentOrder {
    public static func sorted(_ items: [EquippedItem], direction: UInt8) -> [EquippedItem] {
        var layers: [UInt8] = [20, 5, 4, 3, 24, 19, 13, 17, 8, 14, 7, 23, 22, 12, 10, 11, 16, 18, 6, 1, 2]
        layers.removeAll { $0 == 20 }
        let dir = direction & 7
        layers.insert(20, at: dir == 0 ? layers.count : (dir == 3 ? 0 : layers.firstIndex(of: 6)!))
        return items.filter { layers.contains($0.layer) }.sorted {
            let a = layers.firstIndex(of: $0.layer)!, b = layers.firstIndex(of: $1.layer)!
            return a == b ? $0.serial < $1.serial : a < b
        }
    }
}
