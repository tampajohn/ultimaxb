import Foundation

/// Legacy 0x2C server death dialog and the player's explicit response.
public struct DeathState:Equatable {
    public enum Phase:Equatable { case alive, offered, awaitingResurrection, ghost }
    public private(set) var phase:Phase = .alive
    public init() {}
    @discardableResult public mutating func apply(_ packet:Data) throws -> Bool {
        guard packet.first == 0x2C else { return false }
        guard packet.count == 2, packet[1] <= 1 else { throw LoginProtocolError.malformedPacket }
        // Dismissal is sent even when the server subsequently refuses resurrection.
        // Only a living-body update confirms that the player is alive again.
        if packet[1] == 0 { phase = .offered }
        else if phase != .alive { phase = .ghost }
        return true
    }
    /// Call only for authoritative updates of the local player, never predictions
    /// or other mobiles. Bodies 402/403 are the chosen classic era's ghosts.
    @discardableResult public mutating func apply(player: WorldMobile) -> Bool {
        let previous = phase
        if player.body == 402 || player.body == 403 {
            if phase == .alive { phase = .ghost }
        } else {
            phase = .alive
        }
        return phase != previous
    }
    public mutating func response(resurrect:Bool) throws -> Data {
        guard phase == .offered else { throw LoginProtocolError.malformedPacket }
        phase = resurrect ? .awaitingResurrection : .ghost
        return Data([0x2C,resurrect ? 1 : 0])
    }
}
