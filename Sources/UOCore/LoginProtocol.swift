import Foundation

/// Wire formats for the 1.25.32 login flow, checked against OUO's
/// packet_handler.c and packet_manager.c. Transport and encryption are separate.
public enum LoginProtocolError: Error, Equatable {
    case invalidText
    case malformedPacket
    case unsupportedPacket(UInt8)
    case bufferLimit
}

public enum LoginPackets {
    private static func text(_ value: String) throws -> [UInt8] {
        let bytes = Array(value.utf8)
        guard bytes.count < 30, bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else {
            throw LoginProtocolError.invalidText
        }
        return bytes + Array(repeating: 0, count: 30 - bytes.count)
    }

    public static func seed(_ value: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
         UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    public static func account(name: String, password: String, nextKey: UInt8 = 0) throws -> Data {
        Data([0x80] + (try text(name)) + (try text(password)) + [nextKey])
    }

    public static func selectServer(_ index: UInt16) -> Data {
        Data([0xA0, UInt8(index >> 8), UInt8(truncatingIfNeeded: index)])
    }

    /// 1.25.32 character creation with validated allocation and appearance.
    /// OUO validates the plain skin hue and adds the partial-hue bit server-side.
    public static func createCharacter(name: String, female: Bool = false, city: UInt8 = 0, slot: UInt32 = 0, allocation: CharacterAllocation = CharacterAllocation(), appearance: CharacterAppearance = CharacterAppearance()) throws -> Data {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, slot < 5, allocation.validationMessage == nil, appearance.isValid(female:female) else {
            throw LoginProtocolError.invalidText
        }
        var packet = Data([0] + seed(0xEDEDEDED) + seed(0xFFFFFFFF) + [0])
        packet += Data(try text(name))
        packet += Data(repeating: 0, count: 30)
        packet += Data([female ? 1 : 0, UInt8(allocation.strength), UInt8(allocation.dexterity), UInt8(allocation.intelligence)])
        for i in 0..<3 { packet += Data([UInt8(allocation.skillIDs[i]), UInt8(allocation.skillValues[i])]) }
        for value in [appearance.skinHue, appearance.hairStyle, appearance.hairHue, appearance.beardStyle, appearance.beardHue] {
            packet += Data([UInt8(value >> 8), UInt8(value & 255)])
        }
        packet += Data([0, city] + seed(slot) + seed(0))
        return packet
    }

    public static func deleteCharacter(slot: UInt32) throws -> Data {
        guard slot < 5 else { throw LoginProtocolError.invalidText }
        return Data([0x83] + Array(repeating: 0, count: 30) + seed(slot) + seed(0))
    }

    /// The relay authenticates this connection; OUO expects a blank password.
    public static func game(name: String, relay: UInt32) throws -> Data {
        Data([0x91] + seed(relay) + (try text(name)) + Array(repeating: 0, count: 30))
    }

    public static func play(name: String, slot: UInt32, address: UInt32 = 0) throws -> Data {
        Data([0x5D] + seed(0xEDEDEDED) + (try text(name))
             + Array(repeating: 0, count: 30) + seed(slot) + seed(address))
    }
}

public struct LoginServer: Equatable, Sendable {
    public let index: UInt16
    public let name: String
    public let fullness: UInt8
    public let timezone: Int8
    public let address: String
}

public enum LoginResponse: Equatable, Sendable {
    case rejected(UInt8)
    case servers(nextKey: UInt8, entries: [LoginServer])
    case redirect(address: String, port: UInt16, relay: UInt32)

    public static func decode(_ packet: Data) throws -> LoginResponse {
        let bytes = Array(packet)
        guard let opcode = bytes.first else { throw LoginProtocolError.malformedPacket }
        func word(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        }
        func address(_ offset: Int) -> String {
            bytes[offset..<offset + 4].map(String.init).joined(separator: ".")
        }
        switch opcode {
        case 0x82:
            guard bytes.count == 2 else { throw LoginProtocolError.malformedPacket }
            return .rejected(bytes[1])
        case 0x8C:
            guard bytes.count == 11 else { throw LoginProtocolError.malformedPacket }
            let relay = bytes[7..<11].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return .redirect(address: address(1), port: word(5), relay: relay)
        case 0xA8:
            guard bytes.count >= 6, Int(word(1)) == bytes.count else {
                throw LoginProtocolError.malformedPacket
            }
            let count = Int(word(4))
            guard bytes.count == 6 + count * 40 else { throw LoginProtocolError.malformedPacket }
            var entries: [LoginServer] = []
            for index in 0..<count {
                let offset = 6 + index * 40
                let name = String(decoding: bytes[offset + 2..<offset + 34].prefix(while: { $0 != 0 }), as: UTF8.self)
                entries.append(LoginServer(index: word(offset), name: name,
                                           fullness: bytes[offset + 34], timezone: Int8(bitPattern: bytes[offset + 35]),
                                           address: address(offset + 36)))
            }
            return .servers(nextKey: bytes[3], entries: entries)
        default: throw LoginProtocolError.unsupportedPacket(opcode)
        }
    }
}

/// Frames only the uncompressed account-login phase. Never guess a length for
/// an unknown opcode: doing so would silently desynchronize the TCP stream.
public struct LoginFramer {
    private var pending: [UInt8] = []
    public init() {}

    public mutating func receive(_ data: Data) throws -> [Data] {
        guard pending.count + data.count <= 131_072 else { throw LoginProtocolError.bufferLimit }
        pending.append(contentsOf: data)
        var result: [Data] = []
        var offset = 0
        while offset < pending.count {
            let length: Int
            switch pending[offset] {
            case 0x82: length = 2
            case 0x8C: length = 11
            case 0xA8:
                guard pending.count - offset >= 3 else {
                    pending.removeFirst(offset)
                    return result
                }
                length = Int(pending[offset + 1]) << 8 | Int(pending[offset + 2])
                guard length >= 6 else { throw LoginProtocolError.malformedPacket }
            default: throw LoginProtocolError.unsupportedPacket(pending[offset])
            }
            if pending.count - offset < length { break }
            result.append(Data(pending[offset..<offset + length]))
            offset += length
        }
        pending.removeFirst(offset)
        return result
    }
}
