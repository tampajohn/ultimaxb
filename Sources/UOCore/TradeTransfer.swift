import Foundation

/// Tracks a trade-affecting move across separately delivered inventory packets.
/// Removing the old sprite is not proof that the new offer is visible yet.
public struct TradeTransfer {
    public let item:UInt32, destination:UInt32
    private var acknowledged = false, destinationSeen = false, failed = false
    public init(item:UInt32,destination:UInt32) { self.item = item; self.destination = destination }
    public var complete:Bool { failed || (acknowledged && destinationSeen) }
    public mutating func receive(_ packet:Data) throws {
        guard !complete,let opcode = packet.first else { return }
        switch opcode {
        case 0x27:
            guard packet.count == 2 else { throw LoginProtocolError.malformedPacket }
            failed = true
        case 0x28:
            guard packet.count == 5 else { throw LoginProtocolError.malformedPacket }
            // Failed drops can return the item at the player's feet. Wait for
            // its authoritative location rather than treating failure as success.
            break
        case 0x29:
            guard packet.count == 1 else { throw LoginProtocolError.malformedPacket }
            acknowledged = true
        case 0x25,0x3C:
            let contents = try ContainerItem.decode(packet)
            if contents.contains(where: { ($0.serial == item && $0.container == destination) || $0.serial == destination }) { destinationSeen = true }
        case 0x1A:
            if try GroundItem.decode(packet).serial == item { destinationSeen = true }
        default: break
        }
    }
}
