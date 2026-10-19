import Foundation
import XCTest
@testable import UOCore

/// Opt-in test against a disposable OUO instance bound to loopback. Never uses
/// an external hostname or real account; creates one local character per run.
final class OUOIntegrationTests: XCTestCase {
    @MainActor
    func testRealOUOWorldEntry() async throws { try await exerciseWorld(verifySkillTarget: false) }
    @MainActor
    func testSkillTargetWithCompleteScripts() async throws {
        guard ProcessInfo.processInfo.environment["UO_VERIFY_SKILL_TARGET"] == "1" else {
            throw XCTSkip("Local fixture lacks Anatomy script; set UO_VERIFY_SKILL_TARGET=1 with complete scripts")
        }
        try await exerciseWorld(verifySkillTarget: true)
    }
    @MainActor
    func testClassicSpellCasting() async throws {
        guard ProcessInfo.processInfo.environment["UO_VERIFY_SPELLS"] == "1",
              ProcessInfo.processInfo.environment["UO_LOCAL_TEST_CENTER"] == "1" else {
            throw XCTSkip("Requires an isolated complete-script Test Center and UO_VERIFY_SPELLS=1")
        }
        try await exerciseWorld(verifySkillTarget: false, verifySpells: true)
    }
    @MainActor
    func testHidingAndRevealing() async throws {
        guard ProcessInfo.processInfo.environment["UO_VERIFY_HIDING"] == "1",
              ProcessInfo.processInfo.environment["UO_LOCAL_TEST_CENTER"] == "1" else {
            throw XCTSkip("Requires an isolated complete-script Test Center and UO_VERIFY_HIDING=1")
        }
        try await exerciseWorld(verifySkillTarget: false, verifyHiding: true)
    }
    @MainActor
    func testDeathAndResurrectionOutsideGuards() async throws {
        guard ProcessInfo.processInfo.environment["UO_VERIFY_DEATH"] == "1",
              ProcessInfo.processInfo.environment["UO_LOCAL_TEST_CENTER"] == "1",
              ProcessInfo.processInfo.environment["UO_LOCAL_TEST_PORT"] == "2594",
              ProcessInfo.processInfo.environment["UO_LOCAL_TEST_ACCOUNT"] == nil else {
            throw XCTSkip("Requires isolated wilderness-spawn Test Center; see docs/LOCAL_SERVER.md")
        }
        try await exerciseWorld(verifySkillTarget: false, verifySpells: true, verifyDeath: true)
    }
    @MainActor
    private func exerciseWorld(verifySkillTarget: Bool, verifySpells: Bool = false, verifyHiding: Bool = false, verifyDeath: Bool = false) async throws {
        guard let value = ProcessInfo.processInfo.environment["UO_LOCAL_TEST_PORT"],
              let port = UInt16(value) else { throw XCTSkip("Set UO_LOCAL_TEST_PORT for a local OUO integration run") }
        let connection = GameConnection()
        defer { connection.disconnect(notify: false) }
        var framer = GamePacketFramer()
        var world = WorldState()
        var createdCharacter = false
        var entry: WorldEntry?
        var characterStatus: CharacterStatus?
        var skills = SkillState()
        var death = DeathState()
        var skillTarget: TargetRequest?
        var spellEffects: [GraphicEffect] = []
        var spellActions: [MobileAction] = []
        var fixtureMessages: [String] = []
        var complete = false
        var movement = PlayerMovement()
        var moveSent = false
        var moveReply = false
        var positionReply = false
        var failure: String?
        var speechReceived = false
        var counts: [UInt8: Int] = [:]
        let name = ProcessInfo.processInfo.environment["UO_LOCAL_TEST_ACCOUNT"] ?? ("swift" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10))
        connection.onEvent = { event in
            do {
                switch event {
                case .servers(let servers):
                    guard let server = servers.first else { failure = "Empty server list"; return }
                    connection.selectServer(server)
                case .gameData(let bytes):
                    for packet in try framer.receive(bytes) {
                        let opcode = packet.first!
                        counts[opcode, default: 0] += 1
                        if let previous = characterStatus {
                            var stats = previous
                            _ = try stats.apply(packet); characterStatus = stats
                            if stats.needsDetailRefresh(after: previous, opcode: opcode) {
                                connection.send(CharacterStatus.request(serial: stats.serial))
                            }
                        }
                        _ = try world.apply(packet)
                        if verifyDeath {
                            _ = try death.apply(packet)
                            if [0x20, 0x77, 0x78].contains(opcode), let entry {
                                let update = try WorldMobile.decode(packet)
                                if update.serial == entry.serial { death.apply(player: update) }
                            }
                        }
                        if moveSent, let entry, let player = world.mobiles[entry.serial] {
                            if opcode == 0x21 || opcode == 0x22 {
                                if let moved = try movement.receive(packet, player: player) {
                                    world.setPlayerPosition(moved)
                                    moveReply = true
                                    connection.send(PlayerMovement.requestPosition)
                                }
                            } else if opcode == 0x20 {
                                positionReply = true
                            }
                        }
                        switch opcode {
                        case 0x70: if verifySpells { spellEffects.append(try GraphicEffect.decode(packet)) }
                        case 0x6E: if verifySpells { spellActions.append(try MobileAction.decode(packet)) }
                        case 0x3A: try skills.apply(packet)
                        case 0x6C: skillTarget = try TargetRequest.decode(packet)
                        case 0xA9:
                            let characters = try CharacterList.decode(packet).characters
                            if let character = characters.first {
                                connection.send(try LoginPackets.play(name: character.name, slot: character.slot))
                            } else {
                                createdCharacter = true
                                connection.send(Self.fixtureCharacter(name: String(name)))
                            }
                        case 0x27, 0x28:
                            print("Inventory rejection", opcode, packet[1])
                        case 0x1C:
                            fixtureMessages.append(try SpeechMessage.decode(packet).text)
                            if try SpeechMessage.decode(packet).text == "Swift speech fixture" { speechReceived = true }
                        case 0x1B:
                            entry = try WorldEntry.decode(packet)
                            characterStatus = CharacterStatus(serial: entry!.serial)
                        case 0x55: complete = true
                        case 0x53, 0x82: failure = "Server rejected character: \(packet.last!)"
                        default: break
                        }
                    }
                case .failed(let message): failure = message
                case .disconnected: if !complete { failure = "Disconnected before world entry" }
                default: break
                }
            } catch { failure = String(describing: error) }
        }
        try connection.login(host: "127.0.0.1", port: port, name: String(name), password: "local-fixture-only")
        for _ in 0..<600 {
            if complete || failure != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        if verifyDeath {
            let spawn = try XCTUnwrap(entry)
            guard spawn.x == 2603 && spawn.y == 309 else {
                XCTFail("Death test requires the isolated wilderness spawn; refusing to run at a normal town spawn")
                return
            }
        }
        if complete {
            try await Task.sleep(for: .milliseconds(500))
            if let entry, let player = world.mobiles[entry.serial],
               let request = movement.request(direction: (player.direction + 1) & 7, player: player,
                                              at: ProcessInfo.processInfo.systemUptime) {
                moveSent = true
                connection.send(request)
                for _ in 0..<100 {
                    if positionReply || failure != nil { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            XCTAssertTrue(moveReply, "Server did not acknowledge or deny the movement request")
            XCTAssertTrue(positionReply, "Server did not answer position synchronization")
        }
        if complete, let entry,
           let backpack = world.equipment.values.first(where: { $0.owner == entry.serial && $0.layer == 21 }) {
            let previousContentsCount = counts[0x3C] ?? 0
            connection.send(InteractionPackets.use(serial: backpack.serial))
            for _ in 0..<100 {
                if (world.openContainer?.serial == backpack.serial && (counts[0x3C] ?? 0) > previousContentsCount) || failure != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(world.openContainer?.serial, backpack.serial)
            XCTAssertGreaterThan(counts[0x3C] ?? 0, 0, "No backpack contents received")
            try await Task.sleep(for: .seconds(2)) // Let the server finish the container-use action.
            let stack = try XCTUnwrap(world.containerItems.values.first { $0.container == backpack.serial && $0.graphic == 0x0EED && $0.amount > 1 })
            connection.send(try InteractionPackets.pickup(serial: stack.serial, amount: 1))
            connection.send(try InteractionPackets.drop(serial: stack.serial, x: 140, y: 100, container: backpack.serial))
            for _ in 0..<100 {
                if world.containerItems.values.contains(where: { $0.graphic == stack.graphic && $0.amount == 1 && $0.x == 140 && $0.container == backpack.serial }) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let split = try XCTUnwrap(world.containerItems.values.first {
                $0.graphic == stack.graphic && $0.amount == 1 && $0.x == 140 && $0.y == 100 && $0.container == backpack.serial
            }, "Split quantity and drop position not confirmed")
            let remainder = try XCTUnwrap(world.containerItems.values.first {
                $0.serial != split.serial && $0.container == backpack.serial && $0.graphic == stack.graphic && $0.amount == stack.amount - 1
            })
            try await Task.sleep(for: .seconds(2))
            connection.send(try InteractionPackets.pickup(serial: split.serial, amount: 1))
            connection.send(try InteractionPackets.drop(serial: split.serial, x: remainder.x, y: remainder.y, container: remainder.serial))
            for _ in 0..<100 {
                if world.containerItems.values.contains(where: { $0.container == backpack.serial && $0.graphic == stack.graphic && $0.amount == stack.amount }) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertTrue(world.containerItems.values.contains { $0.container == backpack.serial && $0.graphic == stack.graphic && $0.amount == stack.amount }, "Merge quantity not confirmed")
            let worn = try XCTUnwrap(world.equipment.values.first { $0.owner == entry.serial && EquipmentRules.isWearable($0.layer) })
            try await Task.sleep(for: .seconds(2))
            connection.send(try InteractionPackets.pickup(serial: worn.serial, amount: 1))
            connection.send(try InteractionPackets.drop(serial: worn.serial, x: 0xFFFF, y: 0xFFFF, container: backpack.serial))
            for _ in 0..<100 {
                if world.containerItems[worn.serial]?.container == backpack.serial { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertNil(world.equipment[worn.serial], "Unequipped item still worn")
            XCTAssertEqual(world.containerItems[worn.serial]?.container, backpack.serial)
            try await Task.sleep(for: .seconds(2))
            connection.send(try InteractionPackets.pickup(serial: worn.serial, amount: 1))
            connection.send(try InteractionPackets.equip(serial: worn.serial, layer: worn.layer, owner: entry.serial))
            for _ in 0..<100 {
                if world.equipment[worn.serial]?.layer == worn.layer { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(world.equipment[worn.serial]?.owner, entry.serial)
            XCTAssertNil(world.containerItems[worn.serial], "Equipped item still in backpack")
        } else if complete { XCTFail("No equipped backpack received") }
        if let entry {
            connection.send(SkillState.request(serial: entry.serial))
            for _ in 0..<100 {
                if !skills.values.isEmpty || failure != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertGreaterThan(skills.values.count, 40)
            if verifySkillTarget {
            try await Task.sleep(for: .seconds(2))
            connection.send(try SkillState.use(id: 1))
            for _ in 0..<400 {
                if skillTarget != nil || failure != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let target = try XCTUnwrap(skillTarget, "Anatomy did not request a target; fixture server messages: \(fixtureMessages)")
            connection.send(try target.response(nil))
            }
        }
        connection.send(try SpeechPackets.say("Swift speech fixture"))
        for _ in 0..<100 {
            if speechReceived { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        if createdCharacter {
            XCTAssertEqual(characterStatus?.strength, 30)
        } else {
            let expectedStrength = ProcessInfo.processInfo.environment["UO_LOCAL_TEST_CENTER"] == "1" ? 100 : 30
            XCTAssertEqual(characterStatus?.strength, expectedStrength, "Fixture stats did not persist across reconnect/restart")
        }
        if ProcessInfo.processInfo.environment["UO_LOCAL_TEST_CENTER"] == "1" {
            connection.send(try SpeechPackets.say(".set str 100"))
            connection.send(try SpeechPackets.say(".set dex 100"))
            connection.send(try SpeechPackets.say(".set int 100"))
            connection.send(try SpeechPackets.say(".set all 1000"))
            try await Task.sleep(for:.milliseconds(500))
            if let entry { connection.send(SkillState.request(serial:entry.serial)) }

            for _ in 0..<100 {
                if characterStatus?.strength == 100 && characterStatus?.dexterity == 100 && characterStatus?.intelligence == 100 && !skills.values.isEmpty && (skills.values[45] ?? 0) >= 1000 { break }
                try await Task.sleep(for:.milliseconds(50))
            }
            XCTAssertEqual(characterStatus?.strength,100,"Test Center stat command was not applied")
            XCTAssertEqual(characterStatus?.dexterity,100,"DEX did not refresh after stamina maximum changed")
            XCTAssertEqual(characterStatus?.intelligence,100,"INT did not refresh after mana maximum changed")
            XCTAssertEqual(skills.values.count, 46, "Chosen classic skill definitions were not loaded")
            for id in 0..<46 {
                XCTAssertEqual(skills.values[id], 1000, "Test Center skill \(id) did not become 100.0")
            }
        }
        if verifyHiding {
            let player = try XCTUnwrap(entry)
            try await Task.sleep(for: .seconds(2))
            connection.send(try SkillState.use(id: 21))
            for _ in 0..<200 {
                if let mobile = world.mobiles[player.serial], mobile.flags & 0x80 != 0 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let hidden = try XCTUnwrap(world.mobiles[player.serial], "The local player must remain present while hidden")
            XCTAssertNotEqual(hidden.flags & 0x80, 0, "Server did not confirm hiding; fixture messages: \(fixtureMessages)")
            let request = try XCTUnwrap(movement.request(direction: hidden.direction & 7, player: hidden,
                                                        at: ProcessInfo.processInfo.systemUptime))
            connection.send(request)
            for _ in 0..<200 {
                if let mobile = world.mobiles[player.serial], mobile.flags & 0x80 == 0,
                   mobile.x != hidden.x || mobile.y != hidden.y { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let revealed = try XCTUnwrap(world.mobiles[player.serial])
            XCTAssertEqual(revealed.flags & 0x80, 0, "Moving did not reveal the player")
            XCTAssertTrue(revealed.x != hidden.x || revealed.y != hidden.y, "Reveal check requires a confirmed step")
        }
        if verifySpells {
            let player = try XCTUnwrap(entry)
            let backpack = try XCTUnwrap(world.equipment.values.first { $0.owner == player.serial && $0.layer == 21 })
            // Classic casting requires free hands; the fixture starts with a weapon.
            for held in world.equipment.values.filter({ $0.owner == player.serial && [1, 2].contains($0.layer) }) {
                try await Task.sleep(for: .seconds(2))
                connection.send(try InteractionPackets.pickup(serial: held.serial, amount: 1))
                connection.send(try InteractionPackets.drop(serial: held.serial, x: 0xFFFF, y: 0xFFFF, container: backpack.serial))
                for _ in 0..<100 {
                    if world.containerItems[held.serial]?.container == backpack.serial { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                XCTAssertEqual(world.containerItems[held.serial]?.container, backpack.serial)
                XCTAssertNil(world.equipment[held.serial])
            }
            let book = try XCTUnwrap(world.containerItems.values.first { $0.graphic == 0x0EFA && $0.container == backpack.serial })
            // The server throttles item use after the preceding inventory action.
            try await Task.sleep(for: .seconds(2))
            connection.send(InteractionPackets.use(serial: book.serial))
            for _ in 0..<100 {
                if ClassicSpells.contents(book: book.serial, items: Array(world.containerItems.values)).count == 64 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(ClassicSpells.contents(book: book.serial, items: Array(world.containerItems.values)).count, 64)
            for (id, kind): (Int, GraphicEffect.Kind) in (verifyDeath ? [(6, .attached)] : [(6, .attached), (30, .lightning)]) {
                try await Task.sleep(for: .seconds(2))
                skillTarget = nil; spellEffects.removeAll(); spellActions.removeAll()
                connection.send(try ClassicSpells.cast(id: id, book: book.serial))
                for _ in 0..<200 {
                    if skillTarget != nil || failure != nil { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                let target = try XCTUnwrap(skillTarget, "Spell \(id) did not request a target; fixture messages: \(fixtureMessages)")
                let mobile = try XCTUnwrap(world.mobiles[player.serial])
                connection.send(try target.response(TargetSelection(serial: player.serial, x: mobile.x, y: mobile.y, z: mobile.z, graphic: mobile.body)))
                for _ in 0..<200 {
                    if spellEffects.contains(where: { $0.kind == kind && $0.source == player.serial }) { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                XCTAssertTrue(spellEffects.contains { $0.kind == kind && $0.source == player.serial }, "Spell \(id) effect missing")
                XCTAssertTrue(spellActions.contains { $0.serial == player.serial }, "Spell \(id) casting animation missing")
            }
        }
        if verifyDeath {
            let player = try XCTUnwrap(entry)
            let book = try XCTUnwrap(world.containerItems.values.first { $0.graphic == 0x0EFA })
            connection.send(try SpeechPackets.say(".set str 1"))
            for _ in 0..<100 {
                if characterStatus?.health == 1 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(characterStatus?.health, 1)
            try await Task.sleep(for: .seconds(2))
            skillTarget = nil
            connection.send(try ClassicSpells.cast(id: 30, book: book.serial))
            for _ in 0..<200 {
                if skillTarget != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let target = try XCTUnwrap(skillTarget, "Death fixture messages: \(fixtureMessages); phase=\(death.phase)")
            let mobile = try XCTUnwrap(world.mobiles[player.serial])
            connection.send(try target.response(TargetSelection(serial: player.serial, x: mobile.x, y: mobile.y, z: mobile.z, graphic: mobile.body)))
            for _ in 0..<200 {
                if death.phase == .offered, let body = world.mobiles[player.serial]?.body, [402, 403].contains(body) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(death.phase, .offered, "Fixture health=\(characterStatus?.health ?? -1), messages=\(fixtureMessages)")
            guard death.phase == .offered else { return }
            XCTAssertTrue([402, 403].contains(world.mobiles[player.serial]?.body ?? 0))
            XCTAssertTrue(world.items.values.contains { $0.graphic == 0x2006 }, "Death should create a corpse")
            connection.send(try death.response(resurrect: true))
            for _ in 0..<200 {
                if death.phase == .alive, let body = world.mobiles[player.serial]?.body, [400, 401].contains(body) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(death.phase, .alive)
            XCTAssertTrue([400, 401].contains(world.mobiles[player.serial]?.body ?? 0))
        }
        XCTAssertNotNil(characterStatus?.maxHealth)
        XCTAssertNotNil(characterStatus?.gold)
        XCTAssertTrue(speechReceived, "No speech echo received")
        print("OUO packet counts:", counts.sorted { $0.key < $1.key }.map { String(format: "%02X:%d", $0.key, $0.value) }.joined(separator: " "))
        print("OUO world: items=\(world.items.count) mobiles=\(world.mobiles.count)")
        XCTAssertNil(failure)
        XCTAssertTrue(complete, "Did not receive login-complete packet")
        let player = try XCTUnwrap(entry)
        XCTAssertNotNil(world.mobiles[player.serial])
        if let directory = ProcessInfo.processInfo.environment["UO_LOCAL_TEST_ASSETS"],
           let output = ProcessInfo.processInfo.environment["UO_LOCAL_TEST_RENDER"] {
            let assets = try ClientAssets(directory: URL(fileURLWithPath: directory))
            let frame = try WorldRenderer.render(assets, x: player.x, y: player.y,
                                                 groundItems: world.groundTiles,
                                                 mobiles: world.mobiles.values.sorted { $0.serial < $1.serial },
                                                 equipment: Array(world.equipment.values))
            try frame.writeBMP(to: URL(fileURLWithPath: output))
            print("OUO rendered world at \(player.x),\(player.y),\(player.z): missing=\(frame.missingCount)")
        }
        XCTAssertGreaterThan(world.items.count, 0)
        XCTAssertGreaterThan(world.equipment.count, 0)
    }

    private static func fixtureCharacter(name: String) -> Data {
        var packet = Data(repeating: 0, count: 100)
        packet.replaceSubrange(1..<5, with: [0xED,0xED,0xED,0xED])
        packet.replaceSubrange(5..<9, with: [0xFF,0xFF,0xFF,0xFF])
        packet.replaceSubrange(10..<10 + name.utf8.count, with: name.utf8)
        packet.replaceSubrange(70..<80, with: [0,30,15,15,27,50,40,50,17,0])
        packet.replaceSubrange(80..<82, with: [0x83,0xEA])
        return packet
    }
}
