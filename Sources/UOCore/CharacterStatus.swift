import Foundation

public struct CharacterStatus: Equatable {
    public let serial: UInt32
    public private(set) var health: Int?, maxHealth: Int?
    public private(set) var stamina: Int?, maxStamina: Int?
    public private(set) var mana: Int?, maxMana: Int?
    public private(set) var strength: Int?, dexterity: Int?, intelligence: Int?
    public private(set) var gold: UInt32?
    public private(set) var armor: Int?, weight: Int?
    public init(serial: UInt32) { self.serial = serial }
    public static func request(serial: UInt32) -> Data {
        Data([0x34,0xED,0xED,0xED,0xED,4] + LoginPackets.seed(serial))
    }
    /// Apply atomically. Names in status packets are neither retained nor logged.
    @discardableResult public mutating func apply(_ packet: Data) throws -> Bool {
        guard let opcode = packet.first, [0x11,0xA1,0xA2,0xA3].contains(opcode) else { return false }
        var r = PacketReader(packet, offset: 1)
        if opcode == 0x11 {
            guard packet.count >= 43, Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        } else if packet.count != 9 { throw LoginProtocolError.malformedPacket }
        let target = try r.dword()
        var updated = self
        if opcode == 0x11 {
            r.offset = 37 // skip the fixed 30-byte name
            updated.health = Int(try r.word()); updated.maxHealth = Int(try r.word())
            _ = try r.byte()
            let extended = try r.byte()
            if extended != 0 {
                guard packet.count >= 66 else { throw LoginProtocolError.malformedPacket }
                _ = try r.byte()
                updated.strength = Int(try r.word()); updated.dexterity = Int(try r.word()); updated.intelligence = Int(try r.word())
                updated.stamina = Int(try r.word()); updated.maxStamina = Int(try r.word())
                updated.mana = Int(try r.word()); updated.maxMana = Int(try r.word())
                updated.gold = try r.dword(); updated.armor = Int(try r.word()); updated.weight = Int(try r.word())
            } else if packet.count != 43 { throw LoginProtocolError.malformedPacket }
        } else {
            let maximum = Int(try r.word()), current = Int(try r.word())
            switch opcode {
            case 0xA1: updated.health = current; updated.maxHealth = maximum
            case 0xA2: updated.mana = current; updated.maxMana = maximum
            default: updated.stamina = current; updated.maxStamina = maximum
            }
        }
        guard target == serial, updated != self else { return false }
        self = updated; return true
    }
}
