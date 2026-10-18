import Foundation

/// Classic 0x70 graphic-effect envelope. Duration is in 50 ms units.
public struct GraphicEffect: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case moving = 0, lightning = 1, ground = 2, attached = 3, screen = 4 }
    public let kind: Kind
    public let source, destination: UInt32
    public let graphic: Int
    public let x, y, z, destinationX, destinationY, destinationZ: Int
    public let speed: UInt8
    public let duration: TimeInterval
    public let fixedDirection, explode: Bool

    public static func decode(_ packet: Data) throws -> GraphicEffect {
        guard packet.count == 28, packet.first == 0x70 else { throw LoginProtocolError.malformedPacket }
        var reader = PacketReader(packet, offset: 1)
        guard let kind = Kind(rawValue: try reader.byte()) else { throw LoginProtocolError.malformedPacket }
        let source = try reader.dword(), destination = try reader.dword(), graphic = Int(try reader.word())
        let x = Int(try reader.word()), y = Int(try reader.word()), z = Int(Int8(bitPattern: try reader.byte()))
        let dx = Int(try reader.word()), dy = Int(try reader.word()), dz = Int(Int8(bitPattern: try reader.byte()))
        let speed = try reader.byte(), duration = Double(try reader.byte()) * 0.05
        _ = try reader.word() // Reserved.
        let fixed = try reader.byte() != 0, explode = try reader.byte() != 0
        return GraphicEffect(kind: kind, source: source, destination: destination, graphic: graphic,
            x:x,y:y,z:z,destinationX:dx,destinationY:dy,destinationZ:dz,
            speed:speed,duration:duration,fixedDirection:fixed,explode:explode)
    }
}

/// Short-lived visual state only: effects never enter collision, inventory, or hit testing.
public struct StationaryEffects {
    private struct Entry { let effect: GraphicEffect; let started: TimeInterval }
    private var entries: [Entry] = []
    public init() {}
    public var count: Int { entries.count }
    public mutating func append(_ effect: GraphicEffect, at time: TimeInterval) {
        guard time.isFinite, effect.kind == .ground || effect.kind == .attached,
              (1..<0x4000).contains(effect.graphic), effect.duration > 0 else { return }
        expire(at: time)
        if entries.count >= 128 { entries.removeFirst() }
        entries.append(Entry(effect:effect,started:time))
    }
    public mutating func expire(at time: TimeInterval) {
        entries.removeAll { time >= $0.started + $0.effect.duration || time < $0.started }
    }
    public mutating func tiles(at time: TimeInterval, mobiles: [WorldMobile], items: [GroundItem], presentations: [UInt32: MobilePresentation] = [:]) -> [WorldTile] {
        expire(at:time)
        return entries.map { entry in
            let effect = entry.effect
            let mobile = effect.kind == .attached ? mobiles.first { $0.serial == effect.source } : nil
            let item = effect.kind == .attached ? items.first { $0.serial == effect.source } : nil
            let pose = mobile.flatMap { presentations[$0.serial] }
            var tile = WorldTile(x:pose.map { Int(ceil($0.x)) } ?? mobile?.x ?? item?.x ?? effect.x,
                y:pose.map { Int(ceil($0.y)) } ?? mobile?.y ?? item?.y ?? effect.y,
                z:max(mobile?.z ?? item?.z ?? effect.z, pose.map { Int(ceil($0.z)) } ?? -128),
                art:effect.graphic+0x4000,hue:0)
            tile.effectAge = time-entry.started
            tile.effectPose = pose
            return tile
        }
    }
}
