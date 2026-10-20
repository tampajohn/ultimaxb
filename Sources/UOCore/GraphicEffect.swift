import Foundation

/// Classic effect envelope (0x70, hue/blend 0xC0, particle metadata 0xC7). Duration is in 50 ms units.
public struct GraphicEffect: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case moving = 0, lightning = 1, ground = 2, attached = 3, screen = 4 }
    public let kind: Kind
    public let source, destination: UInt32
    public let graphic: Int
    public let x, y, z, destinationX, destinationY, destinationZ: Int
    public let speed: UInt8
    public let duration: TimeInterval
    public let fixedDirection, explode: Bool
    public let hue: Int
    public let blendMode: UInt32

    public static func decode(_ packet: Data) throws -> GraphicEffect {
        let lengths: [UInt8:Int] = [0x70:28, 0xC0:36, 0xC7:49]
        guard let opcode = packet.first, let length = lengths[opcode], packet.count == length else { throw LoginProtocolError.malformedPacket }
        var reader = PacketReader(packet, offset: 1)
        guard let kind = Kind(rawValue: try reader.byte()) else { throw LoginProtocolError.malformedPacket }
        let source = try reader.dword(), destination = try reader.dword(), graphic = Int(try reader.word())
        let x = Int(try reader.word()), y = Int(try reader.word()), z = Int(Int8(bitPattern: try reader.byte()))
        let dx = Int(try reader.word()), dy = Int(try reader.word()), dz = Int(Int8(bitPattern: try reader.byte()))
        let speed = try reader.byte(), duration = Double(try reader.byte()) * 0.05
        _ = try reader.word() // Reserved.
        let fixed = try reader.byte() != 0, explode = try reader.byte() != 0
        let hue = opcode == 0x70 ? 0 : Int(try reader.dword() & 0xFFFF)
        let blend = opcode == 0x70 ? 0 : try reader.dword() % 7
        // C7 particle-specific metadata is not represented by the classic 2D renderer.
        return GraphicEffect(kind: kind, source: source, destination: destination, graphic: graphic,
            x:x,y:y,z:z,destinationX:dx,destinationY:dy,destinationZ:dz,
            speed:speed,duration:duration,fixedDirection:fixed,explode:explode,hue:hue,blendMode:blend)
    }
}

/// Short-lived visual state only: effects never enter collision, inventory, or hit testing.
public struct WorldEffects {
    private struct Entry {
        let effect: GraphicEffect
        let started: TimeInterval
        var position: MobilePresentation?
        var lastUpdate: TimeInterval?
        var impactAt: TimeInterval?
        var lifetime: TimeInterval {
            if let impactAt { return impactAt-started+0.4 }
            return effect.kind == .moving ? 10 : effect.kind == .lightning ? 0.4 : effect.duration
        }
    }
    private var entries: [Entry] = []
    public init() {}
    public var count: Int { entries.count }
    public mutating func append(_ effect: GraphicEffect, at time: TimeInterval) {
        guard time.isFinite else { return }
        guard effect.kind == .lightning ||
            ((effect.kind == .ground || effect.kind == .attached || effect.kind == .moving) &&
             (1..<0x4000).contains(effect.graphic) && (effect.kind == .moving || effect.duration > 0)) else { return }
        expire(at: time)
        if entries.count >= 128 { entries.removeFirst() }
        entries.append(Entry(effect:effect,started:time))
    }
    public mutating func expire(at time: TimeInterval) {
        entries.removeAll { time >= $0.started + $0.lifetime || time < $0.started }
    }
    public mutating func tiles(at time: TimeInterval, mobiles: [WorldMobile], items: [GroundItem], presentations: [UInt32: MobilePresentation] = [:]) -> [WorldTile] {
        expire(at:time)
        func location(_ serial: UInt32, x:Int, y:Int, z:Int) -> MobilePresentation {
            if let pose = presentations[serial] { return pose }
            let mobile = mobiles.first { $0.serial == serial }
            let item = items.first { $0.serial == serial }
            return MobilePresentation(x:Double(mobile?.x ?? item?.x ?? x),
                y:Double(mobile?.y ?? item?.y ?? y),z:Double(mobile?.z ?? item?.z ?? z),walking:false,frame:0)
        }
        var result:[WorldTile] = []
        for index in entries.indices {
            let effect = entries[index].effect
            if effect.kind == .moving {
                let target = location(effect.destination,x:effect.destinationX,y:effect.destinationY,z:effect.destinationZ)
                var position = entries[index].position ?? location(effect.source,x:effect.x,y:effect.y,z:effect.z)
                let dx = (target.x-position.x-target.y+position.y)*22
                let dy = (target.x-position.x+target.y-position.y)*22-(target.z-position.z)*4
                let distance = max(abs(dx),abs(dy))
                let delta = max(0,time-(entries[index].lastUpdate ?? entries[index].started))
                // Classic movement advances five pixels per 20/speed milliseconds.
                let step = delta * 250 * Double(max(1,Int(effect.speed)))
                if entries[index].impactAt == nil {
                    let fraction = distance == 0 ? 1 : min(1,step/distance)
                    position = MobilePresentation(x:position.x+(target.x-position.x)*fraction,
                        y:position.y+(target.y-position.y)*fraction,z:position.z+(target.z-position.z)*fraction,walking:false,frame:0)
                    if fraction == 1 { entries[index].impactAt = time }
                    entries[index].position = position
                    entries[index].lastUpdate = time
                }
                let impact = entries[index].impactAt
                if impact != nil && !effect.explode { continue }
                if impact != nil { position = target }
                var tile = WorldTile(x:Int(ceil(position.x)),y:Int(ceil(position.y)),z:Int(ceil(position.z)),
                    art:0x4000+(impact == nil ? effect.graphic : 0x36CB),hue:effect.hue)
                tile.effectBlendMode = effect.blendMode
                tile.effectAge = time-(impact ?? entries[index].started)
                tile.effectPose = position
                if impact != nil { tile.effectFrameInterval = 0.05 }
                if impact == nil && !effect.fixedDirection { tile.effectRotation = .pi + atan2(dy,dx) }
                result.append(tile)
                continue
            }
            let entry = entries[index]
            let followsSource = effect.kind == .attached || effect.kind == .lightning
            let mobile = followsSource ? mobiles.first { $0.serial == effect.source } : nil
            let item = followsSource ? items.first { $0.serial == effect.source } : nil
            // Lightning is attached to an existing entity, never to a stale packet position.
            if effect.kind == .lightning && mobile == nil && item == nil { continue }
            let pose = mobile.flatMap { presentations[$0.serial] }
            var tile = WorldTile(x:pose.map { Int(ceil($0.x)) } ?? mobile?.x ?? item?.x ?? effect.x,
                y:pose.map { Int(ceil($0.y)) } ?? mobile?.y ?? item?.y ?? effect.y,
                z:max(mobile?.z ?? item?.z ?? effect.z, pose.map { Int(ceil($0.z)) } ?? -128),
                art:effect.kind == .lightning ? 0x4000 : effect.graphic+0x4000,hue:effect.hue)
            tile.effectBlendMode = effect.blendMode
            tile.effectAge = time-entry.started
            tile.effectPose = pose
            if effect.kind == .lightning {
                tile.effectGump = 0x4E20 + min(9, Int((time-entry.started)/0.05))
                tile.effectYOffset = mobile == nil ? 0 : -3
            }
            result.append(tile)
        }
        entries.removeAll { $0.effect.kind == .moving && !$0.effect.explode && $0.impactAt != nil }
        return result
    }
}
