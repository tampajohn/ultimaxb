import Foundation
import XCTest
@testable import UOCore

final class LoginProtocolTests: XCTestCase {
    // Independently constructed server-list and redirect wire fixtures.
    private var serverList: Data {
        Data([0xA8, 0, 46, 0x5D, 0, 1, 0x01, 0x02]
             + Array("Britannia".utf8) + Array(repeating: 0, count: 23)
             + [12, 0xFB, 127, 0, 0, 1])
    }
    private let redirect = Data([0x8C, 127, 0, 0, 1, 0x13, 0x88, 0x12, 0x34, 0x56, 0x78])

    func testAccountAndGamePacketsRespectOldFieldOffsets() throws {
        let login = Array(try LoginPackets.account(name: "test", password: "secret", nextKey: 0x5D))
        XCTAssertEqual(login.count, 62)
        XCTAssertEqual(login[0], 0x80)
        XCTAssertEqual(Array(login[1..<6]), [116, 101, 115, 116, 0])
        XCTAssertEqual(Array(login[31..<38]), [115, 101, 99, 114, 101, 116, 0])
        XCTAssertEqual(login[61], 0x5D)
        let game = Array(try LoginPackets.game(name: "test", relay: 0x12345678))
        XCTAssertEqual(game.count, 65)
        XCTAssertEqual(Array(game[0..<5]), [0x91, 0x12, 0x34, 0x56, 0x78])
        XCTAssertTrue(game[35..<65].allSatisfy { $0 == 0 })
        XCTAssertEqual(LoginPackets.selectServer(0x0102), Data([0xA0, 1, 2]))
        let play = Array(try LoginPackets.play(name: "Avatar", slot: 3))
        XCTAssertEqual(play.count, 73)
        XCTAssertEqual(Array(play[0..<5]), [0x5D, 0xED, 0xED, 0xED, 0xED])
        XCTAssertEqual(Array(play[65..<69]), [0, 0, 0, 3])
    }

    func testBasicCharacterCreationMatchesHistoricalLayout() throws {
        let packet = Array(try LoginPackets.createCharacter(name: "Avatar", female: true, city: 2, slot: 3))
        XCTAssertEqual(packet.count, 100)
        XCTAssertEqual(packet[0], 0)
        XCTAssertEqual(Array(packet[1..<10]), [0xED,0xED,0xED,0xED,0xFF,0xFF,0xFF,0xFF,0])
        XCTAssertEqual(Array(packet[10..<16]), Array("Avatar".utf8))
        XCTAssertEqual(Array(packet[70..<80]), [1,30,15,15,27,50,40,50,17,0])
        XCTAssertEqual(Array(packet[90..<100]), [0,2,0,0,0,3,0,0,0,0])
        XCTAssertThrowsError(try LoginPackets.createCharacter(name: " "))
        XCTAssertThrowsError(try LoginPackets.createCharacter(name: "Avatar", slot: 5))
    }

    func testCredentialValidationDoesNotSilentlyTruncateOrEmbedNull() throws {
        for invalid in [String(repeating: "x", count: 30), "a\0b", "café", "a\nb"] {
            XCTAssertThrowsError(try LoginPackets.account(name: invalid, password: "ok"))
            XCTAssertThrowsError(try LoginPackets.account(name: "ok", password: invalid))
        }
        XCTAssertNoThrow(try LoginPackets.account(name: String(repeating: "x", count: 29), password: ""))
    }

    func testServerListAndRedirectDecodeNetworkByteOrder() throws {
        guard case let .servers(key, entries) = try LoginResponse.decode(serverList) else {
            return XCTFail("Expected server list")
        }
        XCTAssertEqual(key, 0x5D)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].index, 258)
        XCTAssertEqual(entries[0].name, "Britannia")
        XCTAssertEqual(entries[0].timezone, -5)
        XCTAssertEqual(entries[0].address, "127.0.0.1")
        XCTAssertEqual(try LoginResponse.decode(redirect), .redirect(address: "127.0.0.1", port: 5000, relay: 0x12345678))
    }

    func testEveryTCPSplitAndCoalescedResponses() throws {
        let wire = serverList + redirect + Data([0x82, 3])
        let expected = [serverList, redirect, Data([0x82, 3])]
        for split in 0...wire.count {
            var framer = LoginFramer()
            let first = try framer.receive(wire.prefix(split))
            let second = try framer.receive(wire.dropFirst(split))
            XCTAssertEqual(first + second, expected, "Split at \(split)")
        }
        var framer = LoginFramer()
        var received: [Data] = []
        for byte in wire { received += try framer.receive(Data([byte])) }
        XCTAssertEqual(received, expected)
    }

    func testRejectsMalformedAndUnknownPackets() throws {
        for end in 0..<serverList.count {
            XCTAssertThrowsError(try LoginResponse.decode(serverList.prefix(end)))
        }
        var wrongCount = serverList
        wrongCount[5] = 2
        XCTAssertThrowsError(try LoginResponse.decode(wrongCount))
        var framer = LoginFramer()
        XCTAssertThrowsError(try framer.receive(Data([0xA8, 0, 2])))
        var unknown = LoginFramer()
        XCTAssertThrowsError(try unknown.receive(Data([0xFF])))
        var oversized = LoginFramer()
        XCTAssertThrowsError(try oversized.receive(Data(repeating: 0, count: 131_073)))
    }
}
