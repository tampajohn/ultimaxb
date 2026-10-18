import Foundation

public struct ServerMenu:Equatable {
    public struct Option:Equatable {
        public let index:Int, graphic:Int, hue:Int
        public let title:String
    }
    public let serial:UInt32, id:UInt16
    public let title:String
    public let options:[Option]
    public var usesIcons:Bool { options.first?.graphic != 0 && !options.isEmpty }
    public static func decode(_ packet:Data) throws -> ServerMenu {
        guard packet.count >= 11, packet.first == 0x7C else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        guard Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let serial = try r.dword(), id = try r.word()
        func text(_ r:inout PacketReader) throws -> String {
            let length = Int(try r.byte())
            var bytes:[UInt8] = []
            for _ in 0..<length { bytes.append(try r.byte()) }
            return String(data:Data(bytes),encoding:.isoLatin1) ?? ""
        }
        let title = try text(&r), count = Int(try r.byte())
        var options:[Option] = []
        for index in 1..<(count+1) {
            let graphic = Int(try r.word()), hue = Int(try r.word()), title = try text(&r)
            options.append(Option(index:index,graphic:graphic,hue:hue,title:title))
        }
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        return ServerMenu(serial:serial,id:id,title:title,options:options)
    }
    public func response(choice:Int) throws -> Data {
        guard (0...options.count).contains(choice) else { throw LoginProtocolError.malformedPacket }
        let item = choice == 0 ? nil : options[choice-1]
        let graphic = usesIcons ? item?.graphic ?? 0 : 0
        let hue = usesIcons ? item?.hue ?? 0 : 0
        func word(_ value:Int)->[UInt8] { [UInt8(value>>8),UInt8(value&255)] }
        return Data([0x7D]+LoginPackets.seed(serial)+word(Int(id))+word(choice)+word(graphic)+word(hue))
    }
}
