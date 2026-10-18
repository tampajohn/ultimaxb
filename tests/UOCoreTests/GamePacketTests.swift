import Foundation
import XCTest
@testable import UOCore

final class GamePacketTests: XCTestCase {
    private func characters() -> Data {
        var b = [UInt8](repeating: 0, count: 309)
        b[0] = 0xA9; b[1] = 1; b[2] = 53; b[3] = 5
        b.replaceSubrange(124..<130, with: Array("Avatar".utf8))
        return Data(b)
    }
    func testDiagnosticsOnlyContainStructuralMetadata() {
        let summary = GamePacketDiagnostics.summary(characters())
        XCTAssertEqual(summary, "0xA9, 309 bytes, character slots=5, cities=0, trailing bytes=4")
        XCTAssertFalse(summary.contains("Avatar"))
        XCTAssertEqual(GamePacketDiagnostics.summary(Data()), "empty packet")
    }

    func testCharacterListPreservesEmptySlotsAndChecksCityLength() throws {
        let packet = characters()
        let list = try CharacterList.decode(packet)
        XCTAssertEqual(list.characters.count, 1)
        XCTAssertEqual(list.characters[0].slot, 2)
        XCTAssertEqual(list.characters[0].name, "Avatar")
        for end in 0..<packet.count {
            XCTAssertThrowsError(try CharacterList.decode(packet.prefix(end)))
        }
        var invalid = packet
        invalid[304] = 1
        XCTAssertThrowsError(try CharacterList.decode(invalid))
    }
    func testUO1998FixedFiveSlotsWithOccupiedCountAndNineCities() throws {
        // Structural fixture from the live diagnostic; no account data captured.
        var packet = Data(repeating: 0, count: 872)
        packet[0] = 0xA9; packet[1] = 3; packet[2] = 0x68
        packet[3] = 0; packet[304] = 9
        XCTAssertTrue(try CharacterList.decode(packet).characters.isEmpty)
        // One occupied slot does not change the physical five-slot layout.
        packet[3] = 1
        packet.replaceSubrange(184..<190, with: Array("Avatar".utf8))
        let list = try CharacterList.decode(packet)
        XCTAssertEqual(list.characters.count, 1)
        XCTAssertEqual(list.characters[0].slot, 3)
        XCTAssertEqual(list.characters[0].name, "Avatar")
        // Historical packets may append the four-byte flags field.
        var flagged = packet + Data(repeating: 0, count: 4)
        flagged[2] = 0x6C
        XCTAssertEqual(try CharacterList.decode(flagged), list)
        var broken = packet
        broken[304] = 10
        XCTAssertThrowsError(try CharacterList.decode(broken))
    }

    func testStartingCitiesPreserveServerIndicesAndBothNames() throws {
        var packet = Data(repeating: 0, count: 368)
        packet[0] = 0xA9; packet[1] = 1; packet[2] = 112
        packet[304] = 1; packet[305] = 7
        packet.replaceSubrange(306..<313, with: Array("Britain".utf8))
        packet.replaceSubrange(337..<340, with: Array("Inn".utf8))
        let list = try CharacterList.decode(packet)
        XCTAssertEqual(list.cities.count, 1)
        XCTAssertEqual(list.cities[0].index, 7)
        XCTAssertEqual(list.cities[0].name, "Britain")
        XCTAssertEqual(list.cities[0].location, "Inn")
        let request = try LoginPackets.createCharacter(name: "Avatar", city: list.cities[0].index)
        XCTAssertEqual(request[91], 7)
    }

    func testCountSizedCharacterListRemainsSupported() throws {
        var packet = Data(repeating: 0, count: 65)
        packet[0] = 0xA9; packet[2] = 65; packet[3] = 1
        packet.replaceSubrange(4..<10, with: Array("Avatar".utf8))
        XCTAssertEqual(try CharacterList.decode(packet).characters.first?.slot, 0)
    }

    func testGameFramingEverySplitAndWorldEntrySignedHeight() throws {
        var entry = Data(repeating: 0, count: 37)
        entry[0] = 0x1B
        entry.replaceSubrange(1..<5, with: [0x12, 0x34, 0x56, 0x78])
        entry.replaceSubrange(9..<18, with: [1, 0x90, 5, 0x9B, 6, 0x9F, 0xFF, 0xF6, 3])
        let decoded = try WorldEntry.decode(entry)
        XCTAssertEqual(decoded.serial, 0x12345678)
        XCTAssertEqual(decoded.body, 400)
        XCTAssertEqual(decoded.x, 1435)
        XCTAssertEqual(decoded.y, 1695)
        XCTAssertEqual(decoded.z, -10)
        XCTAssertEqual(decoded.direction, 3)
        let wire = characters() + entry + Data([0x55])
        for split in 0...wire.count {
            var framer = GamePacketFramer()
            let a = try framer.receive(wire.prefix(split))
            let b = try framer.receive(wire.dropFirst(split))
            XCTAssertEqual(a + b, [characters(), entry, Data([0x55])])
        }
        var malformed = GamePacketFramer()
        XCTAssertThrowsError(try malformed.receive(Data([0xA9, 0, 2])))
        var unknown = GamePacketFramer()
        XCTAssertThrowsError(try unknown.receive(Data([0xFF])))
    }
}
