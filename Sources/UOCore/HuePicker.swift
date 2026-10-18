import Foundation

/// OUO's legacy HUEPICKER carries serial, type ID, and initial hue.
public struct HuePicker:Equatable {
    public let serial:UInt32, typeID:UInt16, initialHue:UInt16
    public static func decode(_ packet:Data) throws -> HuePicker {
        guard packet.count == 9,packet.first == 0x95 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        return try HuePicker(serial:r.dword(),typeID:r.word(),initialHue:r.word())
    }
    /// Classic 20 × 10 palette, with five shade positions. Hues are one-based.
    public static func hue(column:Int,row:Int,shade:Int)->Int? {
        guard (0..<20).contains(column),(0..<10).contains(row),(0...4).contains(shade) else { return nil }
        return 2+shade+5*(row*20+column)
    }
    public func response(hue:Int) throws -> Data {
        guard (2...1001).contains(hue) else { throw LoginProtocolError.malformedPacket }
        return Data([0x95]+LoginPackets.seed(serial)+[UInt8(typeID>>8),UInt8(typeID&255),UInt8(hue>>8),UInt8(hue&255)])
    }
}
