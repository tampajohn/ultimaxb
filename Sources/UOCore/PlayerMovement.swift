import Foundation

/// Predict immediately, then reconcile a bounded queue against server replies.
public struct PlayerMovement {
    private struct Step {
        let sequence: UInt8
        let predicted: WorldMobile
        let origin: WalkPoint
        let sentAt: TimeInterval
    }
    private var steps: [Step] = []
    public private(set) var rejectedStep: WalkPoint?
    public var pendingCount: Int { steps.count }
    public var predictedPosition: WorldMobile? { steps.last?.predicted }
    public private(set) var awaitingPosition = false
    private var sequence: UInt8 = 0
    private var nextRequestAt: TimeInterval = 0
    private var needsPosition = false
    private var recoverySent = false
    public init() {}
    public mutating func request(direction: UInt8, player: WorldMobile, at time: TimeInterval, predictedZ: Int? = nil) -> Data? {
        guard steps.count < 5, !awaitingPosition, time >= nextRequestAt else { return nil }
        let dir = direction & 0x87
        let delta = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)][Int(dir & 7)]
        let turn = player.direction & 7 != dir & 7
        let predicted = WorldMobile(serial: player.serial, body: player.body,
            x: player.x + (turn ? 0 : delta.0), y: player.y + (turn ? 0 : delta.1),
            z: turn ? player.z : (predictedZ ?? player.z), direction: dir, hue: player.hue, flags: player.flags)
        let packet = Data([0x02, dir, sequence])
        steps.append(Step(sequence: sequence, predicted: predicted, origin: WalkPoint(x:player.x,y:player.y,z:player.z), sentAt: time))
        sequence = sequence == 255 ? 1 : sequence + 1
        nextRequestAt = time + (turn ? 0.1 : (dir & 0x80 != 0 ? 0.2 : 0.4))
        return packet
    }
    public mutating func receive(_ packet: Data, player: WorldMobile) throws -> WorldMobile? {
        guard let opcode = packet.first else { throw LoginProtocolError.malformedPacket }
        if opcode == 0x20 {
            guard packet.count == 19 else { throw LoginProtocolError.malformedPacket }
            if !steps.isEmpty { sequence = 0 }
            steps.removeAll(); awaitingPosition = false; needsPosition = false; recoverySent = false
            return nil // WorldState already applied this authoritative position.
        }
        if opcode == 0x21 {
            guard packet.count == 8 else { throw LoginProtocolError.malformedPacket }
            var r = PacketReader(packet, offset: 2)
            let x = Int(try r.word()), y = Int(try r.word()), dir = try r.byte(), z = Int(Int8(bitPattern: try r.byte()))
            rejectedStep = steps.first(where: { $0.sequence == packet[1] }).flatMap { step in
                let destination = WalkPoint(x:step.predicted.x,y:step.predicted.y,z:step.predicted.z)
                return destination == step.origin ? nil : destination
            }
            steps.removeAll(); sequence = 0; awaitingPosition = true; needsPosition = false
            return WorldMobile(serial: player.serial, body: player.body, x: x, y: y, z: z,
                               direction: dir, hue: player.hue, flags: player.flags)
        }
        guard opcode == 0x22 else { return nil }
        guard packet.count == 3 else { throw LoginProtocolError.malformedPacket }
        guard let first = steps.first, first.sequence == packet[1] else { return nil }
        steps.removeFirst()
        needsPosition = true
        // An older acknowledgement must never roll the display back over later predictions.
        return steps.last?.predicted ?? first.predicted
    }
    public mutating func poll(at time: TimeInterval) -> Data? {
        if let oldest = steps.first, time - oldest.sentAt >= 2, !recoverySent {
            awaitingPosition = true; recoverySent = true
            return Self.requestPosition
        }
        if steps.isEmpty, needsPosition, !awaitingPosition, time >= nextRequestAt + 0.12 {
            awaitingPosition = true
            return Self.requestPosition
        }
        return nil
    }
    public static let requestPosition = Data([0x22, 0, 0])
}

public enum MovementInput {
    /// Combine held directions, including opposing keys, into one of eight facings.
    public static func direction(_ held: [UInt8]) -> UInt8? {
        let steps = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)]
        let delta = Set(held.map { $0 & 7 }).reduce((0,0)) { sum, direction in
            let d = steps[Int(direction)]
            return (sum.0 + d.0, sum.1 + d.1)
        }
        let x = delta.0.signum(), y = delta.1.signum()
        return steps.firstIndex { $0.0 == x && $0.1 == y }.map { UInt8($0) }
    }
}

public struct MovementKeys {
    private var held: [UInt16: UInt8] = [:]
    public init() {}
    public var keyCodes: [UInt16] { Array(held.keys) }
    public var direction: UInt8? { MovementInput.direction(Array(held.values)) }
    public mutating func press(_ key: UInt16, direction: UInt8) {
        let direction = direction & 7
        // The newest opposite direction wins rather than retaining a stale intent.
        held = held.filter { $0.value != (direction + 4) & 7 }
        held[key] = direction
    }
    @discardableResult public mutating func release(_ key: UInt16) -> Bool { held.removeValue(forKey: key) != nil }
    public mutating func clear() { held.removeAll() }
}
