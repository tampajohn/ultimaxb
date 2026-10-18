import Foundation

public struct TargetSelection: Equatable {
    public let serial: UInt32
    public let x: Int, y: Int, z: Int, graphic: Int
    public init(serial: UInt32 = 0, x: Int, y: Int, z: Int, graphic: Int) {
        self.serial = serial; self.x = x; self.y = y; self.z = z; self.graphic = graphic
    }
}
public struct TargetRequest: Equatable {
    public let cursor: UInt32
    public let allowsLocation: Bool
    public let flags: UInt8
    public static func decode(_ packet: Data) throws -> TargetRequest {
        guard packet.count == 19, packet.first == 0x6C, packet[1] <= 1 else { throw LoginProtocolError.malformedPacket }
        var reader = PacketReader(packet, offset: 2)
        return TargetRequest(cursor: try reader.dword(), allowsLocation: packet[1] == 1, flags: try reader.byte())
    }
    public func response(_ selection: TargetSelection?) throws -> Data {
        if let selection {
            // Object cursors also accept statics (trees, furniture, etc.) even
            // though map statics have no serial. Only bare land requires a
            // location cursor; static replies still use the XYZ packet form.
            let isStatic = selection.serial == 0 && (1..<0x4000).contains(selection.graphic)
            guard selection.serial != 0 || isStatic || allowsLocation, (0..<65535).contains(selection.x), (0..<65535).contains(selection.y),
                  (-128...127).contains(selection.z), (0...65535).contains(selection.graphic) else { throw LoginProtocolError.malformedPacket }
        }
        func word(_ n: Int) -> [UInt8] { [UInt8((n >> 8) & 255), UInt8(n & 255)] }
        return Data([0x6C, selection?.serial == 0 ? 1 : 0] + LoginPackets.seed(cursor) + [flags] + LoginPackets.seed(selection?.serial ?? 0) +
            word(selection?.x ?? 65535) + word(selection?.y ?? 65535) + word(selection?.z ?? 0) + word(selection?.graphic ?? 0))
    }
}
