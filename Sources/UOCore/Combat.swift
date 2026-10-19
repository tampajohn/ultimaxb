import Foundation

public enum CombatPackets {
    public static func mode(_ enabled: Bool) -> Data { Data([0x72, enabled ? 1 : 0, 0x32, 0, 0]) }
    public static func attack(_ serial: UInt32) throws -> Data {
        guard serial > 0, serial < 0x40000000 else { throw LoginProtocolError.malformedPacket }
        return Data([0x05] + LoginPackets.seed(serial))
    }
    public static func applyMode(_ packet: Data, to player: WorldMobile) throws -> WorldMobile {
        guard packet.count == 5, packet.first == 0x72, packet[1] <= 1 else { throw LoginProtocolError.malformedPacket }
        let flags = (player.flags & ~0x40) | (packet[1] == 1 ? 0x40 : 0)
        return WorldMobile(serial:player.serial,body:player.body,x:player.x,y:player.y,z:player.z,direction:player.direction,hue:player.hue,flags:flags)
    }
}

/// A single server-confirmed combat target; names are UI-only, never telemetry.
public struct CombatTarget: Equatable {
    public private(set) var serial: UInt32?
    public private(set) var name = ""
    public private(set) var status: CharacterStatus?
    public init() {}
    @discardableResult public mutating func clear() -> Bool {
        guard serial != nil else { return false }
        self = CombatTarget(); return true
    }
    @discardableResult public mutating func apply(_ packet:Data) throws -> Bool {
        let before = self
        switch packet.first {
        case 0x30, 0xAA:
            guard packet.count == 5 else { throw LoginProtocolError.malformedPacket }
            var reader = PacketReader(packet,offset:1)
            let target = try reader.dword()
            guard target < 0x40000000 else { throw LoginProtocolError.malformedPacket }
            if target == 0 { clear() }
            else if target != serial { serial = target; name = ""; status = CharacterStatus(serial:target) }
        case 0xAF:
            if try MobileDeath.decode(packet).serial == serial { clear() }
        case 0x31:
            guard packet.count == 1 else { throw LoginProtocolError.malformedPacket }
            clear()
        case 0x1D:
            guard packet.count == 5 else { throw LoginProtocolError.malformedPacket }
            var reader = PacketReader(packet,offset:1)
            if try reader.dword() == serial { clear() }
        case 0x72:
            guard packet.count == 5, packet[1] <= 1 else { throw LoginProtocolError.malformedPacket }
            if packet[1] == 0 { clear() }
        case 0x11,0xA1,0xA2,0xA3:
            if var stats = status {
                // Parse into a temporary value so malformed packets cannot partially change the target.
                let updated = try stats.apply(packet)
                if packet.first == 0x11 {
                    var reader = PacketReader(packet,offset:3)
                    if try reader.dword() == serial {
                        name = String(bytes:packet[7..<37].prefix { $0 != 0 },encoding:.isoLatin1) ?? ""
                    }
                }
                if updated { status = stats }
            }
        default: break
        }
        return before != self
    }
}
