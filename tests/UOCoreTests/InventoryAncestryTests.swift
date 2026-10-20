import XCTest
@testable import UOCore

final class InventoryAncestryTests:XCTestCase {
    private func item(_ serial:UInt32,parent:UInt32)->Data {
        Data([0x25])+Data(LoginPackets.seed(serial))+Data([0x0E,0x76,0,0,1,0,0,0,0])+Data(LoginPackets.seed(parent))+Data([0,0])
    }
    func testKnownNestedInventoryExcludesOtherRootsAndMissingParents() throws {
        var world=WorldState()
        try world.apply(item(3,parent:2)); try world.apply(item(4,parent:3)); try world.apply(item(5,parent:4))
        XCTAssertTrue(world.isContained(3,in:2)); XCTAssertTrue(world.isContained(5,in:2))
        XCTAssertFalse(world.isContained(2,in:2)); XCTAssertFalse(world.isContained(5,in:8))
        try world.apply(item(3,parent:8))
        XCTAssertFalse(world.isContained(5,in:2),"Moving a bag to the bank must revoke carried ownership")
        XCTAssertTrue(world.isContained(5,in:8))
        try world.apply(item(3,parent:99))
        XCTAssertFalse(world.isContained(5,in:2),"Unknown ancestors cannot establish ownership")
    }
    func testCyclesAndRemovedBagCannotAuthorizeTools() throws {
        var world=WorldState()
        try world.apply(item(3,parent:4)); try world.apply(item(4,parent:3)); try world.apply(item(5,parent:4))
        XCTAssertFalse(world.isContained(5,in:2))
        try world.apply(item(3,parent:2)); XCTAssertTrue(world.isContained(5,in:2))
        try world.apply(Data([0x1D])+Data(LoginPackets.seed(3)))
        XCTAssertFalse(world.isContained(5,in:2))
    }
}
