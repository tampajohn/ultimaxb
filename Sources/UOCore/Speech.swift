import Foundation

public struct SpeechMessage: Equatable {
    public let serial: UInt32
    public let type: UInt8
    public let hue:UInt16
    public let font:UInt16
    public let name: String
    public let text: String
    public init(serial:UInt32,type:UInt8,name:String,text:String,hue:UInt16 = 0,font:UInt16 = 3) {
        self.serial = serial; self.type = type; self.name = name; self.text = text; self.hue = hue; self.font = font
    }
    public static func decode(_ packet: Data) throws -> SpeechMessage {
        guard packet.first == 0x1C, packet.count >= 45 else { throw LoginProtocolError.malformedPacket }
        var reader = PacketReader(packet, offset: 1)
        guard Int(try reader.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let serial = try reader.dword()
        _ = try reader.word()
        let type = try reader.byte()
        let hue = try reader.word(),font = try reader.word()
        guard packet.last == 0 else { throw LoginProtocolError.malformedPacket }
        func string(_ data: Data.SubSequence) -> String {
            String(data: Data(data.prefix { $0 != 0 }), encoding: .isoLatin1) ?? ""
        }
        return SpeechMessage(serial: serial, type: type, name: string(packet[14..<44]), text: string(packet[44...]),hue:hue,font:font)
    }
}

public enum SpeechPackets {
    /// Era 1.25 uses the ASCII speech packet, including banker keywords.
    public static func say(_ text: String) throws -> Data {
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value < 32 }),
              let bytes = text.data(using: .isoLatin1, allowLossyConversion: false), bytes.count <= 200 else {
            throw AssetError("Use 1–200 classic Latin characters for speech.")
        }
        let length = 9 + bytes.count
        return Data([0x03, UInt8(length >> 8), UInt8(length & 255), 0, 0x03, 0xB2, 0, 3]) + bytes + Data([0])
    }
}
