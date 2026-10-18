import Foundation

/// Legacy OUO 0x6F layout. Partner names stay in memory and must not be logged.
public enum TradeEvent:Equatable {
    case opened(partner:UInt32, ownContainer:UInt32, otherContainer:UInt32, name:String)
    case closed(container:UInt32)
    case acceptance(container:UInt32, own:Bool, other:Bool)

    public static func decode(_ packet:Data) throws -> TradeEvent {
        guard packet.first == 0x6F, packet.count >= 17 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        guard Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let action = try r.byte(), serial = try r.dword(), first = try r.dword(), second = try r.dword()
        let hasName = try r.byte()
        var name = ""
        if hasName != 0 {
            guard packet.count == 47 else { throw LoginProtocolError.malformedPacket }
            var bytes:[UInt8] = []
            for _ in 0..<30 { bytes.append(try r.byte()) }
            name = String(data:Data(bytes.prefix { $0 != 0 }),encoding:.isoLatin1) ?? ""
        }
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        switch action {
        case 0:
            guard first != 0, second != 0, first != second, first != UInt32.max, second != UInt32.max else { throw LoginProtocolError.malformedPacket }
            return .opened(partner:serial,ownContainer:first,otherContainer:second,name:name)
        case 1: return .closed(container:serial)
        case 2: return .acceptance(container:serial,own:first != 0,other:second != 0)
        default: throw LoginProtocolError.malformedPacket
        }
    }
}

public struct SecureTrade:Equatable {
    public let partner:UInt32, ownContainer:UInt32, otherContainer:UInt32
    public let partnerName:String
    public private(set) var ownAccepted = false, otherAccepted = false
    public private(set) var pendingAcceptance:Bool?
    public private(set) var cancelling = false, closed = false
    public private(set) var revision:UInt64 = 0
    public private(set) var items:[ContainerItem] = []
    private var withdrawing = false
    public private(set) var awaitingOfferUpdate = false
    public mutating func beginOfferChange() { awaitingOfferUpdate = true; revision &+= 1 }
    public mutating func finishOfferChange() { awaitingOfferUpdate = false }
    public func isOwnOffer(_ serial:UInt32)->Bool? {
        var current = serial, visited:Set<UInt32> = []
        while visited.insert(current).inserted {
            if current == ownContainer { return true }
            if current == otherContainer { return false }
            guard let item = items.first(where: { $0.serial == current }) else { return nil }
            current = item.container
        }
        return nil
    }

    public init?(event:TradeEvent) {
        guard case let .opened(partner,own,other,name) = event else { return nil }
        self.partner = partner; ownContainer = own; otherContainer = other; partnerName = name
    }
    /// OUO uses either box ID in updates, depending on the recipient and operation.
    public mutating func apply(_ event:TradeEvent) {
        switch event {
        case let .closed(container) where container == ownContainer || container == otherContainer:
            closed = true; ownAccepted = false; otherAccepted = false; pendingAcceptance = nil
        case let .acceptance(container,own,other) where !closed && (container == ownContainer || container == otherContainer):
            // An earlier acceptance can still be in flight after a local withdrawal.
            if withdrawing && own { return }
            ownAccepted = own; otherAccepted = other; pendingAcceptance = nil; withdrawing = false
        default: break
        }
    }
    /// Call with the full container snapshot, including known nested contents.
    /// Changed offers revoke consent; a revision also rejects stale UI clicks.
    @discardableResult public mutating func update(items all:[ContainerItem])->Data? {
        guard !closed else { return nil }
        var containers:Set<UInt32> = [ownContainer,otherContainer]
        var selected:[UInt32:ContainerItem] = [:]
        var changed = true
        while changed {
            changed = false
            for item in all where containers.contains(item.container) && selected[item.serial] == nil {
                selected[item.serial] = item
                if containers.insert(item.serial).inserted { changed = true }
            }
        }
        let next = selected.values.sorted { $0.serial < $1.serial }
        guard next != items else { return nil }
        let revoke = ownAccepted || pendingAcceptance == true
        items = next; revision &+= 1; ownAccepted = false; otherAccepted = false
        if revoke { pendingAcceptance = false; withdrawing = true; return response(action:2,accepted:false) }
        return nil
    }
    /// Server acknowledgement determines displayed acceptance; never auto-accept.
    public mutating func setAccepted(_ accepted:Bool, revision expected:UInt64) throws -> Data {
        guard !closed, !cancelling, !awaitingOfferUpdate, pendingAcceptance == nil, expected == revision else { throw LoginProtocolError.malformedPacket }
        pendingAcceptance = accepted
        withdrawing = !accepted
        return response(action:2,accepted:accepted)
    }
    public mutating func cancel() throws -> Data {
        guard !closed,!cancelling else { throw LoginProtocolError.malformedPacket }
        cancelling = true
        return response(action:1,accepted:false)
    }
    private func response(action:UInt8,accepted:Bool)->Data {
        Data([0x6F,0,17,action]+LoginPackets.seed(ownContainer)+LoginPackets.seed(accepted ? 1 : 0)+[0,0,0,0,0])
    }
}
