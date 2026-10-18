import XCTest
@testable import UOCore
final class CorpseEquipmentTests:XCTestCase {
    let corpse:UInt32 = 0x40000001
    let item:UInt32 = 0x40000002
    func layers()->Data { Data([0x89,0,13]+LoginPackets.seed(corpse)+[5]+LoginPackets.seed(item)+[0]) }
    func contents(parent:UInt32)->Data {
        Data([0x25]+LoginPackets.seed(item)+[0x15,0x17,0,0,1,0,10,0,10]+LoginPackets.seed(parent)+[0,33])
    }
    func body()->Data { Data([0x1A,0,16,0xC0,0,0,1,0x20,6,1,0x90,0,100,0,100,0]) }
    func testReorderedEquipmentContentsAndLootRemoval() throws {
        for first in [true,false] {
            var world = WorldState()
            _ = try world.apply(body())
            _ = try world.apply(first ? layers() : contents(parent:corpse))
            XCTAssertTrue(world.groundObjects[0].corpseEquipment.isEmpty)
            _ = try world.apply(first ? contents(parent:corpse) : layers())
            let equipped = try XCTUnwrap(world.groundObjects[0].corpseEquipment.first)
            XCTAssertEqual(equipped.layer,5); XCTAssertEqual(equipped.serial,item); XCTAssertEqual(equipped.hue,33)
            XCTAssertEqual(world.groundTiles[0].corpseEquipment,[equipped])
            XCTAssertTrue(world.equipment.isEmpty,"Corpse clothes must not become worn player equipment")
            _ = try world.apply(contents(parent:99))
            XCTAssertTrue(world.groundObjects[0].corpseEquipment.isEmpty)
        }
    }
    func testMalformedAndDuplicateLayersDoNotChangeState() throws {
        let packet = layers()
        for count in 0..<packet.count { XCTAssertThrowsError(try CorpseEquipment.decode(packet.prefix(count))) }
        var duplicate = Data([0x89,0,18]+LoginPackets.seed(corpse)+[5]+LoginPackets.seed(item)+[5]+LoginPackets.seed(item+1)+[0])
        XCTAssertThrowsError(try CorpseEquipment.decode(duplicate))
        duplicate[12] = 6
        duplicate.replaceSubrange(13..<17,with:LoginPackets.seed(item))
        XCTAssertThrowsError(try CorpseEquipment.decode(duplicate))
        var world = WorldState(); _ = try world.apply(body()); _ = try world.apply(layers()); _ = try world.apply(contents(parent:corpse))
        XCTAssertThrowsError(try world.apply(duplicate))
        XCTAssertEqual(world.groundObjects[0].corpseEquipment.count,1)
        _ = try world.apply(Data([0x1D]+LoginPackets.seed(item)))
        XCTAssertTrue(world.groundObjects[0].corpseEquipment.isEmpty)
    }
}
