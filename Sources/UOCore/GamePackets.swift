import Foundation

/// 1.25.32 packet lengths adapted from OUO packet_utils.c and PROTO_125
/// patches in version.c. Copyright (c) 2020 Draxinar; LICENSES/OUO.txt.
public struct GamePacketFramer {
    private static let lengths: [Int] = [
        100, 5, 3, 32768, 2, 5, 5, 7, 14, 5, 11, 266, 32768, 3, 32768, 61,
        215, 32768, 32768, 10, 6, 9, 1, 32768, 32768, 32768, 32768, 37, 32768, 5, 4, 8,
        19, 8, 3, 26, 7, 20, 5, 2, 5, 1, 5, 2, 2, 17, 15, 10,
        5, 1, 2, 2, 10, 653, 32768, 8, 7, 9, 32768, 32768, 32768, 2, 37, 32768,
        201, 32768, 32768, 553, 713, 5, 32768, 11, 73, 93, 5, 9, 32768, 32768, 6, 2,
        32768, 32768, 32768, 2, 12, 1, 11, 110, 106, 32768, 32768, 4, 2, 73, 32768, 49,
        5, 9, 15, 13, 1, 4, 32768, 21, 32768, 32768, 3, 9, 19, 3, 14, 32768,
        28, 32768, 5, 2, 32768, 35, 16, 17, 32768, 9, 32768, 2, 32768, 13, 2, 32768,
        62, 32768, 2, 39, 69, 2, 32768, 32768, 66, 32768, 32768, 32768, 11, 32768, 32768, 32768,
        19, 65, 32768, 98, 32768, 9, 32768, 2, 32768, 26, 32768, 258, 309, 51, 32768, 32768,
        3, 9, 9, 9, 149, 32768, 32768, 4, 32768, 32768, 5, 32768, 32768, 32768, 32768, 13,
        32768, 32768, 32768,
    ]
    private var pending: [UInt8] = []
    public init() {}
    public mutating func receive(_ data: Data) throws -> [Data] {
        guard pending.count + data.count <= 1_048_576 else { throw LoginProtocolError.bufferLimit }
        pending.append(contentsOf: data)
        var packets: [Data] = []
        var offset = 0
        while offset < pending.count {
            let opcode = Int(pending[offset])
            let extendedLength = opcode == 0xC0 ? 36 : opcode == 0xC7 ? 49 : nil
            guard extendedLength != nil || (opcode < Self.lengths.count && Self.lengths[opcode] != 0) else {
                throw LoginProtocolError.unsupportedPacket(UInt8(opcode))
            }
            var length = extendedLength ?? Self.lengths[opcode]
            if length == 32768 {
                if pending.count - offset < 3 { break }
                length = Int(pending[offset + 1]) << 8 | Int(pending[offset + 2])
                guard length >= 3 else { throw LoginProtocolError.malformedPacket }
            }
            if pending.count - offset < length { break }
            packets.append(Data(pending[offset..<offset + length]))
            offset += length
        }
        pending.removeFirst(offset)
        return packets
    }
}

public struct GameCharacter: Equatable, Sendable {
    public let slot: UInt32
    public let name: String
}

public struct StartingCity: Equatable, Sendable {
    public let index: UInt8
    public let name: String
    public let location: String
}

public struct CharacterList: Equatable, Sendable {
    public let characters: [GameCharacter]
    public let cities: [StartingCity]
    public static func firstEmptySlot(_ characters: [GameCharacter]) -> UInt32? {
        (0..<5).map(UInt32.init).first { slot in !characters.contains(where: { $0.slot == slot }) }
    }
    public static func decodeUpdate(_ data: Data, cities: [StartingCity]) throws -> CharacterList {
        let b = Array(data)
        guard b.count >= 4, b[0] == 0x86, Int(b[1])<<8 | Int(b[2]) == b.count,
              b[3] <= 5, b.count == 4+Int(b[3])*60 else { throw LoginProtocolError.malformedPacket }
        var characters: [GameCharacter] = []
        for slot in 0..<Int(b[3]) {
            let offset = 4+slot*60
            let name = String(decoding:b[offset..<offset+30].prefix { $0 != 0 },as:UTF8.self)
            if !name.isEmpty { characters.append(GameCharacter(slot:UInt32(slot),name:name)) }
        }
        return CharacterList(characters:characters,cities:cities)
    }
    public static func decode(_ data: Data) throws -> CharacterList {
        let b = Array(data)
        guard b.count >= 5, b[0] == 0xA9,
              Int(b[1]) << 8 | Int(b[2]) == b.count else { throw LoginProtocolError.malformedPacket }
        let count = Int(b[3])
        guard count <= 5 else { throw LoginProtocolError.malformedPacket }
        // Historical servers can report occupied slots while always writing five
        // 60-byte records. UO1998's empty-account packet is 872 bytes: header,
        // five empty slots, nine cities, and no feature-flags trailer.
        // Also accept the count-sized layout used by other servers. A layout
        // must consume the entire packet, including an optional flags dword.
        func matches(_ slots: Int) -> Bool {
            let offset = 4 + slots * 60
            guard offset < b.count else { return false }
            let end = offset + 1 + Int(b[offset]) * 63
            return b.count == end || b.count == end + 4
        }
        let slots: Int
        if matches(5) { slots = 5 }
        else if matches(count) { slots = count }
        else { throw LoginProtocolError.malformedPacket }
        var characters: [GameCharacter] = []
        for slot in 0..<slots {
            let offset = 4 + slot * 60
            let name = String(decoding: b[offset..<offset + 30].prefix(while: { $0 != 0 }), as: UTF8.self)
            if !name.isEmpty { characters.append(GameCharacter(slot: UInt32(slot), name: name)) }
        }
        let cityOffset = 4 + slots * 60
        var cities: [StartingCity] = []
        for i in 0..<Int(b[cityOffset]) {
            let offset = cityOffset + 1 + i * 63
            let name = String(decoding: b[offset + 1..<offset + 32].prefix(while: { $0 != 0 }), as: UTF8.self)
            let location = String(decoding: b[offset + 32..<offset + 63].prefix(while: { $0 != 0 }), as: UTF8.self)
            cities.append(StartingCity(index: b[offset], name: name, location: location))
        }
        return CharacterList(characters: characters, cities: cities)
    }
}

public struct WorldEntry: Equatable, Sendable {
    public let serial: UInt32
    public let body: UInt16
    public let x: Int
    public let y: Int
    public let z: Int
    public let direction: UInt8
    public static func decode(_ data: Data) throws -> WorldEntry {
        let b = Array(data)
        guard b.count == 37, b[0] == 0x1B else { throw LoginProtocolError.malformedPacket }
        func word(_ i: Int) -> UInt16 { UInt16(b[i]) << 8 | UInt16(b[i+1]) }
        return WorldEntry(serial: b[1..<5].reduce(0) { ($0 << 8) | UInt32($1) },
                          body: word(9), x: Int(word(11)), y: Int(word(13)),
                          z: Int(Int16(bitPattern: word(15))), direction: b[17])
    }
}

/// Only structural metadata, never packet payloads, account names, or speech.
public enum GamePacketDiagnostics {
    public static func summary(_ packet: Data) -> String {
        let b = Array(packet)
        guard let opcode = b.first else { return "empty packet" }
        var result = String(format: "0x%02X, %d bytes", opcode, b.count)
        if opcode == 0xA9, b.count >= 4 {
            let count = Int(b[3])
            result += ", character slots=\(count)"
            let offset = 4 + count * 60
            if offset < b.count {
                let cities = Int(b[offset])
                result += ", cities=\(cities), trailing bytes=\(b.count - offset - 1 - cities * 63)"
            }
        }
        return result
    }
}
