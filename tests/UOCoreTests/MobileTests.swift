import Foundation
import XCTest
@testable import UOCore

final class MobileTests: XCTestCase {
    let naked = Data([0x77, 0,0,0,1, 1,0x90, 5,0x9B, 6,0x9F, 0xF6,3, 0x83,0xEA, 0,1])
    func testUpdatePositionAndDeleteMobile() throws {
        var world = WorldState()
        XCTAssertTrue(try world.apply(naked))
        let mob = try XCTUnwrap(world.mobiles[1])
        XCTAssertEqual(mob.body, 400)
        XCTAssertEqual(mob.x, 1435)
        XCTAssertEqual(mob.y, 1695)
        XCTAssertEqual(mob.z, -10)
        XCTAssertEqual(mob.hue, 0x83EA)
        var moved = naked
        moved[8] = 0x9C
        XCTAssertTrue(try world.apply(moved))
        XCTAssertEqual(world.mobiles[1]?.x, 1436)
        XCTAssertEqual(world.mobiles.count, 1)
        XCTAssertTrue(try world.apply(Data([0x1D,0,0,0,1])))
        XCTAssertTrue(world.mobiles.isEmpty)
    }
    func testEquippedMobileAndTruncations() throws {
        var packet = Data([0x78, 0, 32]) + naked.dropFirst()
        packet += Data([0x40,0,0,2, 0x80,5, 1, 0x01,0x23, 0,0,0,0])
        XCTAssertEqual(packet.count, 32)
        XCTAssertEqual(try WorldMobile.decode(packet), try WorldMobile.decode(naked))
        for end in 3..<packet.count {
            var bad = Data(packet.prefix(end))
            bad[2] = UInt8(end)
            XCTAssertThrowsError(try WorldMobile.decode(bad))
        }
    }
    func testPlayerUpdateFieldOrder() throws {
        let packet = Data([0x20, 0,0,0,1, 1,0x90, 0, 0x83,0xEA, 0,
                           5,0x9B, 6,0x9F, 0,0, 3,0xF6])
        XCTAssertEqual(try WorldMobile.decode(packet), try WorldMobile.decode(naked).withNotoriety(0))
        var world = WorldState()
        _ = try world.apply(naked)
        _ = try world.apply(packet)
        XCTAssertEqual(world.mobiles[1]?.notoriety,1)
    }
    func testNotorietyClassification() throws {
        for value:UInt8 in 0...7 {
            var packet = naked; packet[16] = value
            let mobile = try WorldMobile.decode(packet)
            XCTAssertEqual(mobile.notoriety,value)
            XCTAssertEqual(mobile.isEnemy,value == 5 || value == 6)
        }
    }
}
