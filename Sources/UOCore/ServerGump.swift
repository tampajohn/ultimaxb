import Foundation

/// Legacy 0xB0 dialogs. Layout strings are data, never executable markup.
public struct ServerGump: Equatable {
    public struct Command: Equatable {
        public let name: String
        public let arguments: [String]
    }
    public let serial: UInt32, id: UInt32
    public let x: Int32, y: Int32
    public let commands: [Command]
    public let texts: [String]

    public static func decode(_ packet: Data) throws -> ServerGump {
        guard packet.first == 0xB0, packet.count >= 23 else { throw LoginProtocolError.malformedPacket }
        var reader = PacketReader(packet, offset: 1)
        guard Int(try reader.word()) == packet.count else { throw LoginProtocolError.malformedPacket }
        let serial = try reader.dword(), id = try reader.dword()
        let x = Int32(bitPattern: try reader.dword()), y = Int32(bitPattern: try reader.dword())
        let length = Int(try reader.word())
        var layout: [UInt8] = []
        for _ in 0..<length { layout.append(try reader.byte()) }
        if layout.last == 0 { layout.removeLast() }
        guard !layout.contains(0), let string = String(bytes: layout, encoding: .isoLatin1) else {
            throw LoginProtocolError.malformedPacket
        }
        let commands = try parseLayout(string)
        let count = Int(try reader.word())
        var texts: [String] = []
        for _ in 0..<count {
            let count = Int(try reader.word())
            var units: [UInt16] = []
            for _ in 0..<count { units.append(try reader.word()) }
            texts.append(String(decoding: units, as: UTF16.self))
        }
        guard reader.offset == packet.count else { throw LoginProtocolError.malformedPacket }
        return ServerGump(serial: serial, id: id, x: x, y: y, commands: commands, texts: texts)
    }

    public static func parseLayout(_ layout: String) throws -> [Command] {
        var result: [Command] = [], tokens: [String] = []
        var token = "", inside = false, quoted = false
        func flush() {
            if !token.isEmpty { tokens.append(token); token = "" }
        }
        for character in layout {
            if inside && character == "@" { quoted.toggle(); token.append(character); continue }
            if quoted { token.append(character); continue }
            if character == "{" {
                guard !inside else { throw LoginProtocolError.malformedPacket }
                inside = true; tokens = []; token = ""
            } else if character == "}" {
                guard inside else { throw LoginProtocolError.malformedPacket }
                flush()
                if let name = tokens.first {
                    result.append(Command(name: name.lowercased(), arguments: Array(tokens.dropFirst())))
                }
                inside = false
            } else if character.isWhitespace {
                if inside { flush() }
            } else {
                guard inside else { throw LoginProtocolError.malformedPacket }
                token.append(character)
            }
        }
        guard !inside, !quoted else { throw LoginProtocolError.malformedPacket }
        return result
    }

    /// Only controls advertised by this dialog may be sent back to the server.
    public func validatedResponse(button: UInt32, switches: [UInt32], entries: [(UInt16,String)]) throws -> Data {
        var buttons: Set<UInt32> = [], allowedSwitches: Set<UInt32> = [], fields: Set<UInt16> = []
        var group = 0, radioGroups: [UInt32:Int] = [:]
        for command in commands {
            let a = command.arguments.compactMap(Int.init)
            guard a.count == command.arguments.count else { continue }
            switch command.name {
            case "group": if let value = a.first { group = value }
            case "endgroup": group = 0
            case "button":
                if a.count >= 7, a[4] != 0, let id = UInt32(exactly:a[6]) { buttons.insert(id) }
            case "checkbox", "radio":
                if a.count >= 6, let id = UInt32(exactly:a[5]) {
                    allowedSwitches.insert(id)
                    if command.name == "radio" { radioGroups[id] = group }
                }
            case "textentry":
                if a.count >= 7, let id = UInt16(exactly:a[5]) { fields.insert(id) }
            default: break
            }
        }
        let cancel = button == 0 && !commands.contains { $0.name == "noclose" }
        let selectedGroups = switches.compactMap { radioGroups[$0] }
        guard (cancel || buttons.contains(button)), Set(switches).isSubset(of:allowedSwitches),
              Set(entries.map { $0.0 }) == fields, Set(selectedGroups).count == selectedGroups.count else {
            throw LoginProtocolError.malformedPacket
        }
        return try response(button:button,switches:switches,entries:entries)
    }

    /// Explicit user reply; counts and lengths are checked before encoding.
    public func response(button: UInt32, switches: [UInt32], entries: [(UInt16, String)]) throws -> Data {
        guard switches.count <= 16378, entries.count <= 16378,
              Set(switches).count == switches.count,
              Set(entries.map { $0.0 }).count == entries.count else { throw LoginProtocolError.malformedPacket }
        var bytes: [UInt8] = [0xB1, 0, 0]
        func dword(_ value: UInt32) { bytes += LoginPackets.seed(value) }
        func word(_ value: UInt16) { bytes += [UInt8(value >> 8), UInt8(value & 255)] }
        dword(serial); dword(id); dword(button); dword(UInt32(switches.count))
        for value in switches { dword(value) }
        dword(UInt32(entries.count))
        for (id, text) in entries {
            let units = Array(text.utf16)
            guard units.count <= 65535, bytes.count + 4 + units.count * 2 <= 65535 else {
                throw LoginProtocolError.malformedPacket
            }
            word(id); word(UInt16(units.count))
            for unit in units { word(unit) }
        }
        guard bytes.count <= 65535 else { throw LoginProtocolError.malformedPacket }
        bytes[1] = UInt8(bytes.count >> 8); bytes[2] = UInt8(bytes.count & 255)
        return Data(bytes)
    }
}
