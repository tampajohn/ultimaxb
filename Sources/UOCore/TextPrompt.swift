import Foundation

public struct TextPrompt:Equatable {
    public enum Format:Equatable { case ascii(id:UInt32); case dialog(parent:UInt8,button:UInt8) }
    public let serial:UInt32, format:Format
    public let title:String, detail:String, allowsCancel:Bool, variant:UInt8, limit:UInt32
    public static func decode(_ packet:Data) throws -> TextPrompt {
        guard packet.count >= 3 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        guard Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let serial = try r.dword()
        func string(_ length:Int,_ r:inout PacketReader) throws -> String {
            var bytes:[UInt8] = []
            for _ in 0..<length { bytes.append(try r.byte()) }
            return String(data:Data(bytes.prefix { $0 != 0 }),encoding:.isoLatin1) ?? ""
        }
        if packet.first == 0x9A {
            let id = try r.dword(); _ = try r.dword()
            guard packet.count >= 16,packet.last == 0 else { throw LoginProtocolError.malformedPacket }
            let title = try string(packet.count-r.offset,&r)
            return TextPrompt(serial:serial,format:.ascii(id:id),title:title.isEmpty ? "Enter your response" : title,detail:"",allowsCancel:true,variant:1,limit:239)
        }
        guard packet.first == 0xAB else { throw LoginProtocolError.malformedPacket }
        let parent = try r.byte(), button = try r.byte(), titleLength = Int(try r.word())
        let title = try string(titleLength,&r), cancel = try r.byte(), variant = try r.byte(), limit = try r.dword()
        let detailLength = Int(try r.word()), detail = try string(detailLength,&r)
        guard r.offset == packet.count, variant <= 2 else { throw LoginProtocolError.malformedPacket }
        return TextPrompt(serial:serial,format:.dialog(parent:parent,button:button),title:title,detail:detail,allowsCancel:cancel != 0,variant:variant,limit:limit)
    }
    public func response(text:String,accepted:Bool) throws -> Data {
        guard accepted || allowsCancel else { throw AssetError("This prompt cannot be cancelled.") }
        let value = accepted ? text : ""
        guard !value.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 10 || $0.value == 13 }),
              let encoded = value.data(using:.isoLatin1,allowLossyConversion:false), encoded.count <= 65519 else {
            throw AssetError("Use single-line classic-client characters.")
        }
        if accepted {
            if variant == 0, !value.isEmpty { throw AssetError("This prompt does not accept text.") }
            if variant == 1, encoded.count > Int(limit) { throw AssetError("The response is too long.") }
            if variant == 2 {
                guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),let number = UInt32(value), number <= limit else {
                    throw AssetError("Enter a whole number from 0 to \(limit).")
                }
            }
        }
        var bytes:[UInt8]
        switch format {
        case .ascii(let id): bytes = [0x9A,0,0]+LoginPackets.seed(serial)+LoginPackets.seed(id)+LoginPackets.seed(accepted ? 1 : 0)
        case .dialog(let parent,let button):
            let length = encoded.count+1
            bytes = [0xAC,0,0]+LoginPackets.seed(serial)+[parent,button,accepted ? 1 : 0,UInt8(length>>8),UInt8(length&255)]
        }
        bytes += encoded; bytes.append(0)
        bytes[1] = UInt8(bytes.count>>8); bytes[2] = UInt8(bytes.count&255)
        return Data(bytes)
    }
}
