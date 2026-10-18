import Foundation

public struct WorldMobile: Equatable, Sendable {
    public let serial: UInt32
    public let body: Int
    public let x: Int, y: Int, z: Int
    public let direction: UInt8
    public let hue: Int
    public let flags: UInt8
    public init(serial: UInt32, body: Int, x: Int, y: Int, z: Int, direction: UInt8 = 3, hue: Int = 0, flags: UInt8 = 0) {
        self.serial = serial; self.body = body; self.x = x; self.y = y; self.z = z
        self.direction = direction; self.hue = hue; self.flags = flags
    }
}

extension WorldMobile {
    public static func decode(_ packet: Data) throws -> WorldMobile {
        guard let opcode = packet.first else { throw LoginProtocolError.malformedPacket }
        if opcode == 0x1B {
            let entry = try WorldEntry.decode(packet)
            return WorldMobile(serial: entry.serial, body: Int(entry.body), x: entry.x, y: entry.y,
                               z: entry.z, direction: entry.direction)
        }
        var r = PacketReader(packet, offset: 1)
        if opcode == 0x78 {
            guard Int(try r.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        } else if (opcode == 0x77 && packet.count == 17) || (opcode == 0x20 && packet.count == 19) {
            // fixed header
        } else { throw LoginProtocolError.malformedPacket }
        let serial = try r.dword(), body = Int(try r.word())
        let x: Int, y: Int, z: Int, direction: UInt8, hue: Int, flags: UInt8
        if opcode == 0x20 {
            _ = try r.byte() // body graphic increment, normally zero
            hue = Int(try r.word()); flags = try r.byte()
            x = Int(try r.word()); y = Int(try r.word())
            _ = try r.word() // facet/reserved field
            direction = try r.byte(); z = Int(Int8(bitPattern: try r.byte()))
        } else {
            x = Int(try r.word()); y = Int(try r.word())
            z = Int(Int8(bitPattern: try r.byte())); direction = try r.byte()
            hue = Int(try r.word()); flags = try r.byte()
            _ = try r.byte() // notoriety
            if opcode == 0x78 {
                // Validate the terminated equipment list; WorldState retains its items.
                var count = 0
                while try r.dword() != 0 {
                    let graphic = try r.word()
                    _ = try r.byte() // layer
                    if graphic & 0x8000 != 0 { _ = try r.word() }
                    count += 1
                    guard count <= 30 else { throw LoginProtocolError.malformedPacket }
                }
            }
        }
        guard r.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        return WorldMobile(serial: serial, body: body, x: x, y: y, z: z, direction: direction, hue: hue, flags: flags)
    }
}
