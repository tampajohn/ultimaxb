import XCTest
@testable import UOCore
final class CombatTests: XCTestCase {
    func testWireRequests() throws {
        XCTAssertEqual(CombatPackets.mode(true),Data([0x72,1,0x32,0,0]))
        XCTAssertEqual(CombatPackets.mode(false),Data([0x72,0,0x32,0,0]))
        XCTAssertEqual(try CombatPackets.attack(0x123456),Data([5,0,0x12,0x34,0x56]))
        XCTAssertThrowsError(try CombatPackets.attack(0))
        XCTAssertThrowsError(try CombatPackets.attack(0x40000001))
    }
    func testServerModePreservesPlayerAndOtherFlags() throws {
        let player = WorldMobile(serial:1,body:400,x:25,y:40,z:-5,direction:7,hue:10,flags:0x84)
        let war = try CombatPackets.applyMode(Data([0x72,1,0,0,0]),to:player)
        XCTAssertEqual(war.flags,0xC4)
        XCTAssertEqual(try CombatPackets.applyMode(Data([0x72,0,0,0,0]),to:war),player)
        XCTAssertThrowsError(try CombatPackets.applyMode(Data([0x72,2,0,0,0]),to:player))
        XCTAssertThrowsError(try CombatPackets.applyMode(Data([0x72,1]),to:player))
    }
}
