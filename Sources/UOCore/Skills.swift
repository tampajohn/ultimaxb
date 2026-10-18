import Foundation

public struct SkillDefinition: Equatable {
    public let id: Int
    public let name: String
    public let usable: Bool
}

public enum SkillAssets {
    public static func decode(index: Data, data: Data) throws -> [SkillDefinition] {
        let idx = Bytes(index), raw = Bytes(data)
        guard idx.count % 12 == 0 else { throw AssetError("Invalid skill index") }
        var result: [SkillDefinition] = []
        for id in 0..<min(256, idx.count/12) {
            let offset = try idx.u32(id*12), length = try idx.u32(id*12+4)
            if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { continue }
            let entry = try raw.slice(offset,length)
            let name = String(data: entry.data.dropFirst().prefix { $0 != 0 }, encoding: .isoLatin1) ?? ""
            guard !name.isEmpty else { continue }
            result.append(SkillDefinition(id:id,name:name,usable:try entry.u8(0) != 0))
        }
        return result
    }
}

/// 1.25.32 skill list/update layout from OUO packet_manager.c (LICENSES/OUO.txt).
/// Values are tenths; this era has no base/cap/lock fields in the packet.
public struct SkillState {
    public private(set) var values: [Int: Int] = [:]
    public init() {}
    public mutating func apply(_ packet: Data) throws {
        var r = PacketReader(packet)
        guard try r.byte() == 0x3A, Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let kind = try r.byte()
        var next = values
        if kind == 0 {
            next = [:]
            while true {
                let id = Int(try r.word())
                if id == 0 { break }
                guard id <= 256, next[id-1] == nil else { throw LoginProtocolError.malformedPacket }
                next[id-1] = Int(try r.word())
            }
        } else if kind == 0xFF {
            let id = Int(try r.word())
            guard id < 256 else { throw LoginProtocolError.malformedPacket }
            next[id] = Int(try r.word())
        } else { throw LoginProtocolError.malformedPacket }
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        values = next
    }
    public static func request(serial: UInt32) -> Data { Data([0x34,0xED,0xED,0xED,0xED,5] + LoginPackets.seed(serial)) }
    public static func use(id: Int) throws -> Data {
        guard (0..<256).contains(id) else { throw AssetError("Invalid skill") }
        let text = Array("\(id) 0".utf8) + [0]
        let length = 4+text.count
        return Data([0x12,UInt8(length>>8),UInt8(length&255),0x24]+text)
    }
}
