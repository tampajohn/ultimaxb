import Foundation

/// Tracks a trade-affecting move across separately delivered inventory packets.
/// Removing the old sprite is not proof that the new offer is visible yet.
public struct TradeTransfer {
    public let item:UInt32, destination:UInt32
    private var acknowledged = false, destinationSeen = false, failed = false
    private var dropRejected = false, returnedItemSeen = false
    public init(item:UInt32,destination:UInt32) { self.item = item; self.destination = destination }
    public var complete:Bool { failed || (dropRejected ? returnedItemSeen : acknowledged && destinationSeen) }
    public mutating func receive(_ packet:Data) throws {
        guard !complete,let opcode = packet.first else { return }
        switch opcode {
        case 0x27:
            guard packet.count == 2 else { throw LoginProtocolError.malformedPacket }
            failed = true
        case 0x28:
            guard packet.count == 5 else { throw LoginProtocolError.malformedPacket }
            // A bounce can restore the old container or drop at the feet, and
            // some server paths omit 0x29. Wait for the returned item itself.
            dropRejected = true
        case 0x29:
            guard packet.count == 1 else { throw LoginProtocolError.malformedPacket }
            acknowledged = true
        case 0x25,0x3C:
            let contents = try ContainerItem.decode(packet)
            if dropRejected && contents.contains(where: { $0.serial == item }) { returnedItemSeen = true }
            if contents.contains(where: { ($0.serial == item && $0.container == destination) || $0.serial == destination }) { destinationSeen = true }
        case 0x2E:
            let equipped = try EquippedItem.decode(packet)
            if equipped.serial == item {
                if dropRejected { returnedItemSeen = true }
                if equipped.owner == destination { destinationSeen = true }
            }
        case 0x1A:
            if try GroundItem.decode(packet).serial == item {
                if dropRejected { returnedItemSeen = true }
                if destination == UInt32.max { destinationSeen = true }
            }
        default: break
        }
    }
}
