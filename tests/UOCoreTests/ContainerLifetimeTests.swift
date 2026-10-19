import XCTest
@testable import UOCore
final class ContainerLifetimeTests:XCTestCase {
    let root:UInt32=0x40000001,bag:UInt32=0x40000002,ore:UInt32=0x40000003,pack:UInt32=0x40000004
    func word(_ value:Int)->[UInt8] { [UInt8(value>>8),UInt8(value&255)] }
    func child(_ serial:UInt32,parent:UInt32)->Data {
        Data([0x25]+LoginPackets.seed(serial)+[0x0E,0x75,0,0,1,0,10,0,10]+LoginPackets.seed(parent)+[0,0])
    }
    func fixture()throws->WorldState {
        var world=WorldState()
        try world.apply(Data([0x77,0,0,0,1,1,0x90,0,100,0,100,0,0,0,0,0,1]))
        try world.apply(Data([0x1A,0,14]+LoginPackets.seed(root)+[0x0E,0x75]+word(133)+word(100)+[0]))
        try world.apply(child(bag,parent:root)); try world.apply(child(ore,parent:bag))
        try world.apply(Data([0x2E]+LoginPackets.seed(pack)+[0x0E,0x75,0,21,0,0,0,1,0,0]))
        try world.apply(child(0x40000005,parent:pack))
        return world
    }
    func testDeleteClearsNestedCacheAndOpenContextOnlyForRemovedTree() throws {
        var world=try fixture()
        try world.apply(Data([0x24]+LoginPackets.seed(bag)+[0,0x3C]))
        try world.apply(Data([0x1D]+LoginPackets.seed(root)))
        XCTAssertEqual(world.removedObjects,[root,bag,ore])
        XCTAssertNil(world.openContainer); XCTAssertNil(world.containerItems[bag]); XCTAssertNil(world.containerItems[ore])
        XCTAssertNotNil(world.containerItems[0x40000005]); XCTAssertNotNil(world.equipment[pack])
        try world.apply(Data([0x3C,0,5,0,0]))
        XCTAssertTrue(world.removedObjects.isEmpty)
        XCTAssertNotNil(world.containerItems[0x40000005])
    }
    func testEmptySnapshotKeepsContainerButRemovesMissingSubtree() throws {
        var world=try fixture()
        try world.apply(Data([0x24]+LoginPackets.seed(root)+[0,0x3C]))
        try world.apply(Data([0x3C,0,5,0,0]))
        XCTAssertEqual(world.openContainer?.serial,root); XCTAssertNotNil(world.items[root])
        XCTAssertEqual(world.removedObjects,[bag,ore]); XCTAssertNil(world.containerItems[ore])
    }
    func testReparentedBagRetainsContentsAndOutOfRangeGroundTreeExpires() throws {
        var world=try fixture()
        try world.apply(child(bag,parent:pack))
        XCTAssertTrue(world.removedObjects.isEmpty); XCTAssertNotNil(world.containerItems[ore])
        world.pruneWorld(around:1)
        XCTAssertEqual(world.removedObjects,[root]); XCTAssertNotNil(world.containerItems[bag]); XCTAssertNotNil(world.containerItems[ore])
        var other=try fixture(); XCTAssertEqual(other.pruneWorld(around:1),3)
        XCTAssertEqual(other.removedObjects,[root,bag,ore]); XCTAssertNotNil(other.containerItems[0x40000005])
    }
    func testMalformedParentCycleCannotLoopDuringDeletion() throws {
        var world=WorldState(); try world.apply(child(bag,parent:ore)); try world.apply(child(ore,parent:bag))
        try world.apply(Data([0x1D]+LoginPackets.seed(bag)))
        XCTAssertEqual(world.removedObjects,[bag,ore]); XCTAssertTrue(world.containerItems.isEmpty)
    }
}
