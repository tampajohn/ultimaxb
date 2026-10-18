import Foundation

/// Legacy ambient/personal light calculation, following ClassicUO IsometricLight
/// (BSD-2-Clause; see LICENSES/ClassicUO.txt). Local light sprites are separate.
public struct WorldLighting:Equatable {
    public private(set) var overall:Int = 0
    public private(set) var personal:Int = 0
    public init() {}
    public var brightness:Double {
        personal < overall ? Double(max(personal,32-overall))/32 : 1
    }
    @discardableResult public mutating func apply(_ packet:Data,player:UInt32?) throws -> Bool {
        switch packet.first {
        case 0x4F:
            guard packet.count == 2 else { throw LoginProtocolError.malformedPacket }
            overall = min(30,Int(packet[1])); return true
        case 0x4E:
            guard packet.count == 6 else { throw LoginProtocolError.malformedPacket }
            var reader = PacketReader(packet,offset:1)
            let serial = try reader.dword(),level = try reader.byte()
            guard serial == player else { return false }
            personal = min(30,Int(level)); return true
        default: return false
        }
    }
}
