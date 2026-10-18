import Foundation

/// Classic 0x6E animation command. This never changes world position.
public struct MobileAction: Equatable {
    public let serial: UInt32
    public let action: Int, frameCount: Int, repeatCount: Int
    public let backward: Bool, repeatAnimation: Bool
    public let delay: Int
    public static func decode(_ packet:Data) throws -> MobileAction {
        guard packet.count == 14, packet.first == 0x6E else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        let serial = try r.dword(), action = Int(try r.word()), frames = Int(try r.word()), repeats = Int(try r.word())
        let backward = try r.byte(), repeatFlag = try r.byte(), delay = Int(try r.byte())
        // These are wire values, not asset bounds. Unknown action groups may be
        // absent locally; the renderer handles that without dropping the session.
        // Classic clients treat any nonzero flag as true.
        return MobileAction(serial:serial,action:action,frameCount:frames,repeatCount:repeats,backward:backward != 0,repeatAnimation:repeatFlag != 0,delay:delay)
    }
}
