import Foundation

/// Classic music indices, derived from CrossUO SoundManager.cpp's MIDI catalog.
/// Copyright (c) 2016 Hotride. MIT license: LICENSES/CrossUO-MIT.txt.
public enum MusicCatalog {
    public struct Track: Sendable { public let name:String; public let loops:Bool }
    public static let tracks:[Track] = [
        Track(name:"oldult01",loops:true),
        Track(name:"create1",loops:false),
        Track(name:"dragflit",loops:false),
        Track(name:"oldult02",loops:true),
        Track(name:"oldult03",loops:true),
        Track(name:"oldult04",loops:true),
        Track(name:"oldult05",loops:true),
        Track(name:"oldult06",loops:true),
        Track(name:"stones2",loops:true),
        Track(name:"britain1",loops:true),
        Track(name:"britain2",loops:true),
        Track(name:"bucsden",loops:true),
        Track(name:"jhelom",loops:false),
        Track(name:"lbcastle",loops:false),
        Track(name:"linelle",loops:false),
        Track(name:"magincia",loops:true),
        Track(name:"minoc",loops:true),
        Track(name:"ocllo",loops:true),
        Track(name:"samlethe",loops:false),
        Track(name:"serpents",loops:true),
        Track(name:"skarabra",loops:true),
        Track(name:"trinsic",loops:true),
        Track(name:"vesper",loops:true),
        Track(name:"wind",loops:true),
        Track(name:"yew",loops:true),
        Track(name:"cave01",loops:false),
        Track(name:"dungeon9",loops:false),
        Track(name:"forest_a",loops:false),
        Track(name:"intown01",loops:false),
        Track(name:"jungle_a",loops:false),
        Track(name:"mountn_a",loops:false),
        Track(name:"plains_a",loops:false),
        Track(name:"sailing",loops:false),
        Track(name:"swamp_a",loops:false),
        Track(name:"tavern01",loops:false),
        Track(name:"tavern02",loops:false),
        Track(name:"tavern03",loops:false),
        Track(name:"tavern04",loops:false),
        Track(name:"combat1",loops:false),
        Track(name:"combat2",loops:false),
        Track(name:"combat3",loops:false),
        Track(name:"approach",loops:false),
        Track(name:"death",loops:false),
        Track(name:"victory",loops:false),
        Track(name:"btcastle",loops:false),
        Track(name:"nujelm",loops:true),
        Track(name:"dungeon2",loops:false),
        Track(name:"cove",loops:true),
        Track(name:"moonglow",loops:true),
        Track(name:"oldult02",loops:false),
        Track(name:"serpents",loops:true),
        Track(name:"oldult04",loops:false),
        Track(name:"dragflit",loops:false),
        Track(name:"create1",loops:false),
        Track(name:"approach",loops:false),
        Track(name:"combat3",loops:false),
        Track(name:"jungle_a",loops:false),
    ]
    public static func track(_ id:Int) -> Track? { tracks.indices.contains(id) ? tracks[id] : nil }
    public static func decode(_ packet:Data) throws -> Int {
        guard packet.count == 3, packet.first == 0x6D else { throw LoginProtocolError.malformedPacket }
        return Int(packet[1])*256 + Int(packet[2])
    }
}
