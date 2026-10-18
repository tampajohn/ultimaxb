import Foundation

public struct ContainerItem: Equatable, Sendable {
    public let serial: UInt32
    public let graphic: Int
    public let amount: Int
    public let x: Int, y: Int
    public let container: UInt32
    public let hue: Int

    public init(serial: UInt32, graphic: Int, amount: Int, x: Int, y: Int, container: UInt32, hue: Int) {
        self.serial = serial; self.graphic = graphic; self.amount = amount
        self.x = x; self.y = y; self.container = container; self.hue = hue
    }

    public var displayGraphic: Int {
        guard [0x0EEA, 0x0EED, 0x0EF0].contains(graphic) else { return graphic }
        return graphic + (amount > 5 ? 2 : amount > 1 ? 1 : 0)
    }

    static func read(_ r: inout PacketReader) throws -> ContainerItem {
        let serial = try r.dword(), graphic = Int(try r.word())
        _ = try r.byte() // OUO 1.25.32 stackable/reserved byte, not an art increment.
        let amount = Int(try r.word()), x = Int(try r.word()), y = Int(try r.word())
        let container = try r.dword(), hue = Int(try r.word())
        return ContainerItem(serial: serial, graphic: graphic, amount: amount, x: x, y: y, container: container, hue: hue)
    }
    public static func decode(_ packet: Data) throws -> [ContainerItem] {
        guard let opcode = packet.first else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet, offset: 1)
        if opcode == 0x25 {
            guard packet.count == 20 else { throw LoginProtocolError.malformedPacket }
            return [try read(&r)]
        }
        guard opcode == 0x3C, Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let count = Int(try r.word())
        guard packet.count == 5 + count * 19 else { throw LoginProtocolError.malformedPacket }
        return try (0..<count).map { _ in try read(&r) }
    }
}

public struct OpenContainer: Equatable, Sendable {
    public let serial: UInt32
    public let graphic: UInt16
    public static func decode(_ packet: Data) throws -> OpenContainer {
        guard packet.first == 0x24, packet.count == 7 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet, offset: 1)
        return OpenContainer(serial: try r.dword(), graphic: try r.word())
    }
}

public enum InteractionPackets {
    public static func equip(serial: UInt32, layer: UInt8, owner: UInt32) throws -> Data {
        guard EquipmentRules.isWearable(layer) else { throw LoginProtocolError.malformedPacket }
        return Data([0x13] + LoginPackets.seed(serial) + [layer] + LoginPackets.seed(owner))
    }
    public static func pickup(serial: UInt32, amount: Int) throws -> Data {
        guard (1...65535).contains(amount) else { throw LoginProtocolError.malformedPacket }
        return Data([0x07] + LoginPackets.seed(serial) + [UInt8(amount >> 8), UInt8(amount & 255)])
    }
    public static func drop(serial: UInt32, x: Int, y: Int, container: UInt32, z: Int = 0) throws -> Data {
        guard (0...65535).contains(x), (0...65535).contains(y), (-128...127).contains(z) else { throw LoginProtocolError.malformedPacket }
        return Data([0x08] + LoginPackets.seed(serial) + [UInt8(x >> 8), UInt8(x & 255), UInt8(y >> 8), UInt8(y & 255), UInt8(truncatingIfNeeded:z)] + LoginPackets.seed(container))
    }
    public static func inspect(serial: UInt32) -> Data { Data([0x09] + LoginPackets.seed(serial)) }
    public static func use(serial: UInt32) -> Data { Data([0x06] + LoginPackets.seed(serial)) }
}

public enum EquipmentRules {
    public static func isWearable(_ layer: UInt8) -> Bool {
        (1...24).contains(layer) && ![11,15,16,21].contains(layer)
    }
}

extension WorldState {
    /// Build a transfer without changing local ownership; only server replies move the item.
    public func movePackets(serial:UInt32, amount:Int, player:UInt32, x:Int, y:Int, target:UInt32, z:Int = 0) throws -> [Data] {
        let available:Int?
        if let item = equipment[serial] {
            available = item.owner == player && EquipmentRules.isWearable(item.layer) ? 1 : nil
        } else {
            available = containerItems[serial]?.amount ?? items[serial]?.amount
        }
        guard let available, amount > 0, amount <= max(1,available) else { throw LoginProtocolError.malformedPacket }
        return [try InteractionPackets.pickup(serial:serial,amount:amount),
                try InteractionPackets.drop(serial:serial,x:x,y:y,container:target,z:z)]
    }
}
