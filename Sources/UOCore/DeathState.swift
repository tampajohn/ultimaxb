import Foundation

/// Legacy 0x2C server death dialog and the player's explicit response.
public struct DeathState:Equatable {
    public enum Phase:Equatable { case alive, offered, awaitingResurrection, ghost }
    public private(set) var phase:Phase = .alive
    public init() {}
    @discardableResult public mutating func apply(_ packet:Data) throws -> Bool {
        guard packet.first == 0x2C else { return false }
        guard packet.count == 2, packet[1] <= 1 else { throw LoginProtocolError.malformedPacket }
        phase = packet[1] == 1 ? .alive : .offered
        return true
    }
    public mutating func response(resurrect:Bool) throws -> Data {
        guard phase == .offered else { throw LoginProtocolError.malformedPacket }
        phase = resurrect ? .awaitingResurrection : .ghost
        return Data([0x2C,resurrect ? 1 : 0])
    }
}
