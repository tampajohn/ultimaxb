import Foundation

/// 1.25 book packets, checked against local OUO book.c (LICENSES/OUO.txt).
public struct ClassicBook: Equatable {
    public let serial: UInt32
    public let writable: Bool
    public let pageCount: Int
    public var title, author: String
    public var pages: [Int:[String]] = [:]

    public static func pageSerial(_ data:Data) throws -> UInt32 {
        guard data.count >= 9, data.first == 0x66 else { throw LoginProtocolError.malformedPacket }
        var r=PacketReader(data,offset:1)
        guard Int(try r.word()) == data.count else { throw LoginProtocolError.malformedPacket }
        return try r.dword()
    }

    public static func decodeHeader(_ data: Data) throws -> ClassicBook {
        guard data.count == 98, data.first == 0x93 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(data,offset:1)
        let serial = try r.dword(), writable = try r.byte() != 0, count = Int(try r.word())
        guard count <= 1024 else { throw LoginProtocolError.bufferLimit }
        func text(_ count:Int) throws -> String {
            var bytes:[UInt8] = []
            for _ in 0..<count { bytes.append(try r.byte()) }
            return String(data:Data(bytes.prefix { $0 != 0 }),encoding:.isoLatin1) ?? ""
        }
        return try ClassicBook(serial:serial,writable:writable,pageCount:count,title:text(60),author:text(30))
    }
    public mutating func receivePages(_ data: Data) throws {
        guard data.count >= 9, data.first == 0x66 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(data,offset:1)
        guard Int(try r.word()) == data.count, try r.dword() == serial else { throw LoginProtocolError.malformedPacket }
        let count = Int(try r.word())
        guard count <= pageCount else { throw LoginProtocolError.malformedPacket }
        var updates:[Int:[String]] = [:]
        for _ in 0..<count {
            let page = Int(try r.word()), lines = Int(try r.word())
            guard (1...max(1,pageCount)).contains(page), page <= pageCount,
                  lines <= 128, updates[page] == nil else { throw LoginProtocolError.malformedPacket }
            var text:[String] = []
            for _ in 0..<lines {
                var bytes:[UInt8] = []
                while true {
                    let byte = try r.byte()
                    if byte == 0 { break }
                    guard bytes.count < 1024 else { throw LoginProtocolError.bufferLimit }
                    bytes.append(byte)
                }
                text.append(String(data:Data(bytes),encoding:.isoLatin1) ?? "")
            }
            updates[page] = text
        }
        guard r.offset == data.count else { throw LoginProtocolError.malformedPacket }
        pages.merge(updates,uniquingKeysWith:{_,new in new})
    }
    public func request(page:Int) throws -> Data {
        guard page > 0, page <= pageCount else { throw AssetError("Invalid book page.") }
        return Data([0x66,0,13]+LoginPackets.seed(serial)+[0,1,UInt8(page>>8),UInt8(page&255),255,255])
    }
    private func encoded(_ value:String,limit:Int) throws -> Data {
        guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              let bytes=value.data(using:.isoLatin1,allowLossyConversion:false),bytes.count<=limit else {
            throw AssetError("Use classic characters within the book's text limits.")
        }
        return bytes
    }
    public func writeHeader(title:String,author:String) throws -> Data {
        guard writable else { throw AssetError("This book is read-only.") }
        let t=try encoded(title,limit:59),a=try encoded(author,limit:29)
        return Data([0x93]+LoginPackets.seed(serial)+[1,UInt8(pageCount>>8),UInt8(pageCount&255)])
            + t + Data(repeating:0,count:60-t.count) + a + Data(repeating:0,count:30-a.count)
    }
    public func writePage(_ page:Int,lines:[String]) throws -> Data {
        guard writable, page > 0, page <= pageCount, pages[page] != nil else { throw AssetError("Load a writable page before editing it.") }
        guard lines.count <= 8 else { throw AssetError("A classic book page holds eight lines.") }
        var data=Data([0x66,0,0]+LoginPackets.seed(serial)+[0,1,UInt8(page>>8),UInt8(page&255),0,UInt8(lines.count)])
        for line in lines { data += try encoded(line,limit:127); data.append(0) }
        data[1]=UInt8(data.count>>8); data[2]=UInt8(data.count&255)
        return data
    }
}
