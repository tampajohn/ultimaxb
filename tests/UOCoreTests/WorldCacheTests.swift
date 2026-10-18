import XCTest
@testable import UOCore

final class WorldCacheTests: XCTestCase {
    private func word(_ n: Int) -> [UInt8] { [UInt8(n >> 8), UInt8(n & 255)] }
    private func mobile(_ serial: UInt32, x: Int) -> Data {
        Data([0x77] + LoginPackets.seed(serial) + [1,0x90] + word(x) + word(100) + [0,0,0,0,0,1])
    }
    private func ground(_ serial: UInt32, x: Int) -> Data {
        Data([0x1A,0,14] + LoginPackets.seed(serial) + [0x0E,0xED] + word(x) + word(100) + [0])
    }
    func testBoundaryEquipmentAndInventoryLifetimes() throws {
        var world = WorldState()
        try world.apply(mobile(1, x: 100))
        try world.apply(mobile(2, x: 133))
        try world.apply(ground(0x40000001, x: 132))
        try world.apply(ground(0x40000002, x: 133))
        try world.apply(Data([0x2E,0x40,0,0,3,0x15,0x17,0,5,0,0,0,2,0,0]))
        let inventory = Data([0x25,0x40,0,0,4,0x0E,0xED,0,0,5,0,60,0,70,0x40,0,0,5,0,0])
        try world.apply(inventory)
        XCTAssertEqual(world.pruneWorld(around: 1), 3)
        XCTAssertNotNil(world.items[0x40000001])
        XCTAssertNil(world.items[0x40000002]); XCTAssertNil(world.mobiles[2])
        XCTAssertTrue(world.equipment.isEmpty)
        XCTAssertEqual(world.containerItems[0x40000004]?.amount, 5)
        // Returning scenery is accepted again when the server resends it.
        try world.apply(mobile(1, x: 133)); try world.apply(ground(0x40000002, x: 133))
        XCTAssertEqual(world.pruneWorld(around: 1), 0)
        XCTAssertNotNil(world.items[0x40000002])
    }
    func testTravellingDoesNotAccumulateOldScenery() throws {
        var world = WorldState()
        for x in 100..<1100 {
            try world.apply(mobile(1, x: x))
            try world.apply(ground(0x40000000 + UInt32(x), x: x))
            world.pruneWorld(around: 1)
            XCTAssertLessThanOrEqual(world.items.count, 33)
        }
        XCTAssertEqual(world.items.count, 33)
    }
}
