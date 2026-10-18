import Foundation

public struct CorpseEquipment {
    public let serial:UInt32
    public let layers:[UInt8:UInt32]
    public static func decode(_ packet:Data) throws -> CorpseEquipment {
        guard packet.first == 0x89, (8...138).contains(packet.count) else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        guard Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let corpse = try r.dword()
        var layers:[UInt8:UInt32] = [:], serials:Set<UInt32> = []
        while true {
            let layer = try r.byte()
            if layer == 0 { break }
            let item = try r.dword()
            guard layer <= 26, layers[layer] == nil, item != 0, serials.insert(item).inserted else { throw LoginProtocolError.malformedPacket }
            layers[layer] = item
        }
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        return CorpseEquipment(serial:corpse,layers:layers)
    }
}
