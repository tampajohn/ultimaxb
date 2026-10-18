import XCTest
@testable import UOCore
final class EquipmentTransferTests:XCTestCase {
    func testEquippedPickaxeCreatesTransferAndWaitsForServer() throws {
        var world = WorldState()
        let serial:UInt32 = 0x40000007, bag:UInt32 = 0x40000008
        try world.apply(Data([0x2E,0x40,0,0,7,0x0E,0x86,0,1,0,0,0,1,0,0]))
        let packets = try world.movePackets(serial:serial,amount:1,player:1,x:80,y:100,target:bag)
        XCTAssertEqual(packets,[Data([7,0x40,0,0,7,0,1]),Data([8,0x40,0,0,7,0,80,0,100,0,0x40,0,0,8])])
        XCTAssertNotNil(world.equipment[serial])
        XCTAssertNil(world.containerItems[serial])
        XCTAssertThrowsError(try world.movePackets(serial:serial,amount:2,player:1,x:80,y:100,target:bag))
        XCTAssertThrowsError(try world.movePackets(serial:serial,amount:1,player:2,x:80,y:100,target:bag))
        // 0x25 is the server's authoritative move from equipment into the bag.
        try world.apply(Data([0x25,0x40,0,0,7,0x0E,0x86,0,0,1,0,80,0,100,0x40,0,0,8,0,0]))
        XCTAssertNil(world.equipment[serial])
        XCTAssertEqual(world.containerItems[serial]?.container,bag)
    }
    func testBackpackAndHairCannotBeDraggedOffAsEquipment() throws {
        for layer:UInt8 in [11,21] {
            var world = WorldState()
            try world.apply(Data([0x2E,0x40,0,0,7,0x0E,0x86,0,layer,0,0,0,1,0,0]))
            XCTAssertThrowsError(try world.movePackets(serial:0x40000007,amount:1,player:1,x:80,y:100,target:0x40000008))
        }
    }
}
