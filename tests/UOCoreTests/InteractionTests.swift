import Foundation
import XCTest
@testable import UOCore

final class InteractionTests: XCTestCase {
    func testCrossContainerUpdatesPreserveOtherContents() throws {
        var world = WorldState()
        func row(_ serial: UInt8, _ parent: UInt8, _ amount: UInt8) -> Data {
            Data([0x40,0,0,serial, 0x0E,0xED,0, 0,amount, 0,60,0,70, 0x40,0,0,parent, 0,0])
        }
        try world.apply(Data([0x25]) + row(1, 10, 20))
        try world.apply(Data([0x25]) + row(2, 11, 30))
        try world.apply(Data([0x25]) + row(1, 11, 20))
        XCTAssertEqual(world.containerItems.values.filter { $0.container == 0x4000000A }.count, 0)
        XCTAssertEqual(world.containerItems.values.filter { $0.container == 0x4000000B }.count, 2)
        try world.apply(Data([0x3C,0,24,0,1]) + row(3, 10, 5))
        XCTAssertEqual(world.containerItems.count, 3)
        try world.apply(Data([0x24,0x40,0,0,10,0,60]))
        try world.apply(Data([0x3C,0,5,0,0]))
        XCTAssertEqual(world.containerItems.count, 2)
        XCTAssertEqual(world.containerItems[0x40000001]?.container, 0x4000000B)
    }
    func testEquipPacketAndProtectedLayers() throws {
        XCTAssertEqual(try InteractionPackets.equip(serial: 0x40000001, layer: 5, owner: 2), Data([0x13,0x40,0,0,1,5,0,0,0,2]))
        for layer: UInt8 in [0,11,15,16,21,25,29,255] {
            XCTAssertThrowsError(try InteractionPackets.equip(serial: 1, layer: layer, owner: 2))
        }
    }
    func testInventoryPackets() throws {
        XCTAssertEqual(try InteractionPackets.pickup(serial: 0x12345678, amount: 300), Data([7,0x12,0x34,0x56,0x78,1,44]))
        XCTAssertEqual(try InteractionPackets.drop(serial: 0x12345678, x: 120, y: 80, container: 0x40000001), Data([8,0x12,0x34,0x56,0x78,0,120,0,80,0,0x40,0,0,1]))
        XCTAssertThrowsError(try InteractionPackets.pickup(serial: 1, amount: 0))
        XCTAssertThrowsError(try InteractionPackets.drop(serial: 1, x: -1, y: 1, container: 2))
    }
    func testContainerSnapshotsAndTransitionsAreAtomic() throws {
        var world = WorldState()
        let row = Data([0x40,0,0,1, 0x0E,0xED,1, 0,42, 0,30,0,40, 0x40,0,0,2, 0,5])
        let snapshot = Data([0x3C,0,24,0,1]) + row
        try world.apply(snapshot)
        XCTAssertEqual(world.containerItems[0x40000001]?.amount, 42)
        XCTAssertEqual(world.containerItems[0x40000001]?.graphic, 0x0EED)
        XCTAssertEqual(world.containerItems[0x40000001]?.container, 0x40000002)
        let before = world.containerItems
        for length in 3..<snapshot.count {
            var truncated = Data(snapshot.prefix(length)); truncated[2] = UInt8(length)
            XCTAssertThrowsError(try world.apply(truncated))
            XCTAssertEqual(world.containerItems, before)
        }
        try world.apply(Data([0x24,0x40,0,0,2,0,0x3C]))
        try world.apply(Data([0x3C,0,5,0,0]))
        XCTAssertTrue(world.containerItems.isEmpty)
        try world.apply(Data([0x25]) + row)
        try world.apply(Data([0x2E,0x40,0,0,1,0x15,0x17,0,5,0,0,0,1,0,0]))
        XCTAssertTrue(world.containerItems.isEmpty)
        XCTAssertEqual(world.equipment.count, 1)
    }
    func testFacingObjectUsesDirectionAndPrioritizesDoors() throws {
        try AssetTests().withClient { root in
            var metadata = Data(repeating: 0, count: 512 * 836 + 1188)
            metadata[512 * 836 + 4 + 37 + 3] = 0x20 // Graphic 1 is a door.
            try metadata.write(to: root.appendingPathComponent("TILEDATA.MUL"))
            let assets = try ClientAssets(directory: root)
            func item(_ serial: UInt32, _ graphic: Int, _ x: Int, _ y: Int) -> GroundItem {
                GroundItem(serial: serial, graphic: graphic, amount: 1, x: x, y: y, z: 0, direction: 0, hue: 0, flags: 0)
            }
            let items = [item(1,0,11,10), item(2,1,11,10), item(3,1,10,9)]
            let player = WorldMobile(serial: 4, body: 400, x: 10, y: 10, z: 0, direction: 0x82)
            XCTAssertEqual(try WorldInteraction.facingItem(player: player, items: items, assets: assets)?.serial, 2)
            XCTAssertNil(try WorldInteraction.facingItem(player: player, items: [items[2]], assets: assets))
            XCTAssertEqual(InteractionPackets.use(serial: 0x40000002), Data([6,0x40,0,0,2]))
        }
    }
    func testItemHitTestingRejectsTransparentPixels() throws {
        try AssetTests().withClient { root in
            let helper = AssetTests()
            let raw = helper.words([0,0,4,2,0,6,1,2,0x7C00,0,0,0,0,0])
            try raw.write(to: root.appendingPathComponent("ART.MUL"))
            var index = Data(repeating: 0xFF, count: 0x4001 * 12)
            index.replaceSubrange(0x4000 * 12..<0x4001 * 12, with: helper.words([0,0,raw.count,0,0,0]))
            try index.write(to: root.appendingPathComponent("ARTIDX.MUL"))
            let assets = try ClientAssets(directory: root)
            let item = GroundItem(serial: 1, graphic: 0, amount: 1, x: 10, y: 10, z: 0, direction: 0, hue: 0, flags: 0)
            let camera = WorldCamera(x: 10, y: 10)
            XCTAssertEqual(try WorldHitTest.groundItem(assets: assets, items: [item], camera: camera, screenX: 49, screenY: 92, width: 100, height: 100)?.serial, 1)
            XCTAssertNil(try WorldHitTest.groundItem(assets: assets, items: [item], camera: camera, screenX: 50, screenY: 92, width: 100, height: 100))
        }
    }
}
