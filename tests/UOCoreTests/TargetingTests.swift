import XCTest
@testable import UOCore

final class TargetingTests: XCTestCase {
    func request(_ type: UInt8 = 0) throws -> TargetRequest {
        try TargetRequest.decode(Data([0x6C,type,0x12,0x34,0x56,0x78,1] + Array(repeating: 0, count: 12)))
    }
    func testObjectLocationAndCancelPackets() throws {
        let object = try request()
        XCTAssertEqual(try object.response(TargetSelection(serial: 0x40000001, x: 100, y: 200, z: -5, graphic: 0xEED)),
            Data([0x6C,0,0x12,0x34,0x56,0x78,1,0x40,0,0,1,0,100,0,200,0xFF,0xFB,0x0E,0xED]))
        let point = TargetSelection(x: 100, y: 200, z: 0, graphic: 0)
        XCTAssertThrowsError(try object.response(point))
        XCTAssertEqual(try request(1).response(point)[1], 1)
        let cancel = try object.response(nil)
        XCTAssertEqual(cancel.count, 19)
        XCTAssertEqual(Array(cancel[11..<15]), [255,255,255,255])
        for count in 0..<19 { XCTAssertThrowsError(try TargetRequest.decode(Data(cancel.prefix(count)))) }
        XCTAssertThrowsError(try object.response(TargetSelection(serial: 1, x: -1, y: 1, z: 0, graphic: 3)))
    }
    func testObjectCursorAcceptsStaticTreeWithoutSerial() throws {
        let object = try request()
        let tree = TargetSelection(x:2557,y:377,z:0,graphic:0x0CCA)
        let packet = try object.response(tree)
        XCTAssertEqual(packet,Data([0x6C,1,0x12,0x34,0x56,0x78,1,0,0,0,0,0x09,0xFD,0x01,0x79,0,0,0x0C,0xCA]))
        XCTAssertThrowsError(try object.response(TargetSelection(x:2557,y:377,z:0,graphic:0)))
        XCTAssertThrowsError(try object.response(TargetSelection(x:2557,y:377,z:0,graphic:0xFFFF)))
    }
    func testMobileHitUsesAnimationTransparency() throws {
        try AssetTests().withClient { root in
            let raw = AnimationTests().record()
            var index = Data(repeating: 0xFF, count: 35025 * 12)
            index.replaceSubrange(35020*12..<35021*12, with: [0,0,0,0,UInt8(raw.count & 255),UInt8(raw.count >> 8),0,0,0,0,0,0])
            try index.write(to: root.appendingPathComponent("ANIM.IDX")); try raw.write(to: root.appendingPathComponent("ANIM.MUL"))
            let assets = try ClientAssets(directory: root)
            let mobile = WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 0, direction: 3)
            XCTAssertEqual(try WorldHitTest.mobile(assets: assets, mobiles: [mobile], presentations: [:], camera: WorldCamera(x: 10,y: 10), screenX: 479, screenY: 380)?.serial, 1)
            XCTAssertNil(try WorldHitTest.mobile(assets: assets, mobiles: [mobile], presentations: [:], camera: WorldCamera(x: 10,y: 10), screenX: 479, screenY: 381))
        }
    }
    func testNoDrawMarkersDoNotRender() throws {
        try AssetTests().withClient { root in
            let assets = try ClientAssets(directory:root)
            let baseline = try WorldRenderer.render(assets,x:10,y:10)
            let withMarker = try WorldRenderer.render(assets,x:10,y:10,groundItems:[WorldTile(x:10,y:10,z:0,art:0x4001,hue:0)])
            XCTAssertEqual(baseline.rgba,withMarker.rgba)
            XCTAssertTrue(try assets.isNoDraw(graphic:0x2198))
            XCTAssertTrue(try assets.isNoDraw(graphic:0x21BC))
            XCTAssertFalse(try assets.isNoDraw(graphic:0x3EDD)) // boat mast must remain visible
        }
    }
    func testLandLocationHit() throws {
        try AssetTests().withClient { root in
            let map = try FileHandle(forWritingTo: root.appendingPathComponent("MAP0.MUL"))
            try map.seek(toOffset: UInt64(513*196+4+18*3)); try map.write(contentsOf: Data([3,0,0])); try map.close()
            let assets = try ClientAssets(directory: root)
            let selected = try WorldHitTest.location(assets: assets, camera: WorldCamera(x: 10,y: 10), screenX: 480, screenY: 382, visibility: WorldVisibility())
            XCTAssertEqual(selected, TargetSelection(x: 10, y: 10, z: 0, graphic: 0))
            XCTAssertEqual(Array(try request(1).response(selected)[17..<19]),[0,0])
        }
    }
}
