import Foundation

public struct VendorOffer: Equatable {
    public let item: ContainerItem
    public let price: UInt32
    public let name: String
}
public enum VendorPackets {
    /// Prices have no serials: OUO writes 0x3C backwards and 0x74 forwards; reverse the container wire order.
    public static func offers(_ packet: Data, contents: [ContainerItem]) throws -> [VendorOffer] {
        var r = PacketReader(packet)
        guard try r.byte() == 0x74, Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let container = try r.dword(), count = Int(try r.byte())
        let items = contents.filter { $0.container == container }
        guard count <= 250, items.count == count else { throw LoginProtocolError.malformedPacket }
        var result: [VendorOffer] = []
        for item in items.reversed() {
            let price = try r.dword(), length = Int(try r.byte())
            guard length > 0 else { throw LoginProtocolError.malformedPacket }
            var name: [UInt8] = []
            for _ in 0..<length { name.append(try r.byte()) }
            result.append(VendorOffer(item:item,price:price,name:String(bytes:name.prefix { $0 != 0 },encoding:.isoLatin1) ?? "Item"))
        }
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        return result
    }
    public static func buy(vendor: UInt32, offers: [VendorOffer], quantities: [UInt32:Int]) throws -> Data {
        let chosen = offers.filter { quantities[$0.item.serial,default:0] > 0 }
        guard !chosen.isEmpty, chosen.count <= 250, Set(chosen.map { $0.item.serial }).count == chosen.count,
              quantities.allSatisfy({ entry in entry.value >= 0 && offers.contains(where: { $0.item.serial == entry.key }) }) else { throw LoginProtocolError.malformedPacket }
        let length = 8+chosen.count*7
        var data = Data([0x3B,UInt8(length>>8),UInt8(length&255)] + LoginPackets.seed(vendor) + [2])
        for offer in chosen {
            let count = quantities[offer.item.serial]!
            guard count <= offer.item.amount, count <= 65535 else { throw LoginProtocolError.malformedPacket }
            data.append(contentsOf:[0x1A] + LoginPackets.seed(offer.item.serial) + [UInt8(count>>8),UInt8(count&255)])
        }
        return data
    }
    /// Sell offers carry their own serials, graphics, quantities and prices.
    public static func sellOffers(_ packet:Data) throws -> (vendor:UInt32, offers:[VendorOffer]) {
        var r = PacketReader(packet)
        guard try r.byte() == 0x9E, Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let vendor = try r.dword(), count = Int(try r.word())
        guard count <= 250 else { throw LoginProtocolError.bufferLimit }
        var offers: [VendorOffer] = []
        var serials = Set<UInt32>()
        for _ in 0..<count {
            let serial = try r.dword(), graphic = Int(try r.word()), hue = Int(try r.word()), amount = Int(try r.word()), price = UInt32(try r.word()), length = Int(try r.word())
            guard serials.insert(serial).inserted, length <= 1024 else { throw LoginProtocolError.malformedPacket }
            var bytes: [UInt8] = []
            for _ in 0..<length { bytes.append(try r.byte()) }
            let item = ContainerItem(serial:serial,graphic:graphic,amount:amount,x:0,y:0,container:0,hue:hue)
            offers.append(VendorOffer(item:item,price:price,name:String(bytes:bytes.prefix { $0 != 0 },encoding:.isoLatin1) ?? "Item"))
        }
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        return (vendor,offers)
    }
    public static func sell(vendor:UInt32, offers:[VendorOffer], quantities:[UInt32:Int]) throws -> Data {
        // Share quantity/identity validation with buying; the wire layouts differ.
        _ = try buy(vendor:vendor,offers:offers,quantities:quantities)
        let chosen = offers.filter { quantities[$0.item.serial,default:0] > 0 }
        let length = 9+chosen.count*6
        var data = Data([0x9F,UInt8(length>>8),UInt8(length&255)] + LoginPackets.seed(vendor) + [UInt8(chosen.count>>8),UInt8(chosen.count&255)])
        for offer in chosen {
            let n = quantities[offer.item.serial]!
            data.append(contentsOf:LoginPackets.seed(offer.item.serial)+[UInt8(n>>8),UInt8(n&255)])
        }
        return data
    }
    public static func cancelSell(vendor:UInt32) -> Data { Data([0x9F,0,9]+LoginPackets.seed(vendor)+[0,0]) }
    public static func closedVendor(_ packet: Data) throws -> UInt32 {
        var reader = PacketReader(packet)
        guard try reader.byte() == 0x3B, Int(try reader.word()) == packet.count, packet.count == 8 else { throw LoginProtocolError.malformedPacket }
        let serial = try reader.dword(); _ = try reader.byte()
        return serial
    }
    public static func cancel(vendor: UInt32) -> Data { Data([0x3B,0,8] + LoginPackets.seed(vendor) + [0]) }
}
