import Foundation

/// Classic 0xAF: dying mobile, corpse (or zero), alternate death animation.
public struct MobileDeath: Equatable {
    public let serial:UInt32, corpse:UInt32
    public let alternate:Bool
    public static func decode(_ packet:Data) throws -> MobileDeath {
        guard packet.count == 13,packet.first == 0xAF else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        let serial = try r.dword(), corpse = try r.dword(), variant = try r.dword()
        guard serial > 0,serial < 0x40000000,corpse == 0 || (0x40000000..<0x80000000).contains(corpse) else {
            throw LoginProtocolError.malformedPacket
        }
        return MobileDeath(serial:serial,corpse:corpse,alternate:variant != 0)
    }
}

/// Bounded visual snapshots survive authoritative mobile removal without being
/// selectable or changing world state. Corpse art is withheld only while falling.
public struct DeathAnimations {
    private struct Track {
        let event:MobileDeath, mobile:WorldMobile, equipment:[EquippedItem]
        let pose:MobilePresentation, action:Int, frames:Int, started:Double
    }
    private var tracks:[UInt32:Track] = [:]
    public init() {}
    public mutating func play(_ event:MobileDeath,mobile:WorldMobile,equipment:[EquippedItem],
                              pose:MobilePresentation?,frames:Int,at time:Double) {
        expire(at:time)
        guard frames > 0, mobile.serial == event.serial, tracks[event.serial] == nil else { return }
        if tracks.count >= 128, let oldest = tracks.min(by:{$0.value.started < $1.value.started})?.key { tracks.removeValue(forKey:oldest) }
        let serial = event.serial | 0x80000000
        let snapshot = WorldMobile(serial:serial,body:mobile.body,x:mobile.x,y:mobile.y,z:mobile.z,
                                   direction:mobile.direction,hue:mobile.hue,flags:mobile.flags,notoriety:mobile.notoriety)
        let worn = equipment.filter { $0.owner == event.serial }.map {
            EquippedItem(serial:$0.serial,graphic:$0.graphic,layer:$0.layer,owner:serial,hue:$0.hue)
        }
        let position = pose ?? MobilePresentation(x:Double(mobile.x),y:Double(mobile.y),z:Double(mobile.z),walking:false,frame:0)
        tracks[event.serial] = Track(event:event,mobile:snapshot,equipment:worn,pose:position,
            action:CorpseArt.deathAction(body:mobile.body,alternate:event.alternate),frames:min(512,frames),started:time)
    }
    public mutating func expire(at time:Double) { tracks = tracks.filter { time < $0.value.started + Double($0.value.frames)*0.1 } }
    public var isAnimating:Bool { !tracks.isEmpty }
    public func hides(_ mobile:WorldMobile)->Bool {
        tracks[mobile.serial]?.mobile.body == mobile.body
    }
    public var hiddenCorpses:Set<UInt32> { Set(tracks.values.map(\.event.corpse).filter { $0 != 0 }) }
    public var mobiles:[WorldMobile] { tracks.values.map(\.mobile).sorted { $0.serial < $1.serial } }
    public var equipment:[EquippedItem] { tracks.values.flatMap(\.equipment) }
    public func presentations(at time:Double)->[UInt32:MobilePresentation] {
        Dictionary(uniqueKeysWithValues:tracks.values.map { track in
            (track.mobile.serial,MobilePresentation(x:track.pose.x,y:track.pose.y,z:track.pose.z,walking:false,
                frame:min(track.frames-1,max(0,Int((time-track.started)/0.1))),action:track.action))
        })
    }
}
