import XCTest
@testable import UOCore

final class CharacterStatusTests: XCTestCase {
    func full() -> Data {
        var packet = Data([0x11,0,66,0,0,0,1]) + Data(repeating: 0, count: 30)
        packet += Data([0,25,0,30,0,1,0, 0,30,0,15,0,16, 0,12,0,15,0,9,0,16, 0,0,1,44, 0,10,0,55])
        return packet
    }
    func testFullAndIncrementalUpdates() throws {
        var status = CharacterStatus(serial: 1)
        XCTAssertTrue(try status.apply(full()))
        XCTAssertEqual(status.health, 25); XCTAssertEqual(status.maxHealth, 30)
        XCTAssertEqual(status.strength, 30); XCTAssertEqual(status.dexterity, 15); XCTAssertEqual(status.intelligence, 16)
        XCTAssertEqual(status.stamina, 12); XCTAssertEqual(status.mana, 9)
        XCTAssertEqual(status.gold, 300); XCTAssertEqual(status.armor, 10); XCTAssertEqual(status.weight, 55)
        for (opcode, value): (UInt8, UInt8) in [(0xA1,20),(0xA2,8),(0xA3,11)] {
            XCTAssertTrue(try status.apply(Data([opcode,0,0,0,1,0,30,0,value])))
        }
        XCTAssertEqual(status.health, 20); XCTAssertEqual(status.mana, 8); XCTAssertEqual(status.stamina, 11)
        XCTAssertEqual(status.gold, 300)
        let before = status
        XCTAssertFalse(try status.apply(Data([0xA1,0,0,0,2,0,30,0,1])))
        XCTAssertEqual(status, before)
        var short = Data(full().prefix(43)); short[2] = 43; short[42] = 0
        XCTAssertTrue(try status.apply(short)); XCTAssertEqual(status.health, 25); XCTAssertEqual(status.gold, 300)
    }
    func testMalformedStatusDoesNotPartiallyMutate() throws {
        var status = CharacterStatus(serial: 1)
        try status.apply(full()); let before = status
        for count in 1..<66 {
            var packet = Data(full().prefix(count))
            if count >= 3 { packet[2] = UInt8(count) }
            XCTAssertThrowsError(try status.apply(packet)); XCTAssertEqual(status, before)
        }
        XCTAssertEqual(CharacterStatus.request(serial: 1), Data([0x34,0xED,0xED,0xED,0xED,4,0,0,0,1]))
    }
}
