import XCTest
@testable import UOCore

final class GraphicEffectTests: XCTestCase {
    private func packet(kind:UInt8 = 3, duration:UInt8 = 20) -> Data {
        Data([0x70,kind,0,0,0,1,0,0,0,2,0x37,0x6A,
              0x09,0xC4,0x01,0xF4,0xFB,0x09,0xC5,0x01,0xF5,0x80,5,duration,0,0,1,0])
    }
    func testDecodeAndValidation() throws {
        let effect = try GraphicEffect.decode(packet())
        XCTAssertEqual(effect.kind,.attached)
        XCTAssertEqual(effect.source,1); XCTAssertEqual(effect.destination,2)
        XCTAssertEqual(effect.graphic,0x376A)
        XCTAssertEqual(effect.x,2500); XCTAssertEqual(effect.y,500); XCTAssertEqual(effect.z,-5)
        XCTAssertEqual(effect.destinationZ,-128); XCTAssertEqual(effect.duration,1)
        XCTAssertTrue(effect.fixedDirection); XCTAssertFalse(effect.explode)
        for length in 0..<28 { XCTAssertThrowsError(try GraphicEffect.decode(packet().prefix(length))) }
        XCTAssertThrowsError(try GraphicEffect.decode(packet()+Data([0])))
        XCTAssertThrowsError(try GraphicEffect.decode(packet(kind:5)))
        XCTAssertEqual(try GraphicEffect.decode(packet(kind:4)).kind,.screen)
    }
    func testAttachmentLifetimeAndGroundStability() throws {
        var effects = StationaryEffects()
        effects.append(try GraphicEffect.decode(packet()),at:10)
        effects.append(try GraphicEffect.decode(packet(kind:2)),at:10)
        let mobile = WorldMobile(serial:1,body:400,x:2510,y:510,z:20)
        let tiles = effects.tiles(at:10.5,mobiles:[mobile],items:[])
        XCTAssertEqual(tiles.count,2)
        XCTAssertEqual(tiles[0].x,2510); XCTAssertEqual(tiles[0].z,20)
        XCTAssertEqual(tiles[1].x,2500); XCTAssertEqual(tiles[1].z,-5)
        XCTAssertEqual(tiles[0].effectAge,0.5)
        let pose = MobilePresentation(x:2509.5,y:509.5,z:19.5,walking:true,frame:1)
        let moving = effects.tiles(at:10.6,mobiles:[mobile],items:[],presentations:[1:pose])
        XCTAssertEqual(moving[0].effectPose,pose)
        XCTAssertEqual(moving[0].x,2510); XCTAssertEqual(moving[0].z,20)
        XCTAssertNil(moving[1].effectPose)
        XCTAssertTrue(effects.tiles(at:11,mobiles:[],items:[]).isEmpty)
        XCTAssertEqual(effects.count,0)
    }
    func testBoundedStateAndUnsupportedKinds() throws {
        var effects = StationaryEffects()
        for kind:UInt8 in [0,1,4] { effects.append(try GraphicEffect.decode(packet(kind:kind)),at:0) }
        effects.append(try GraphicEffect.decode(packet(duration:0)),at:0)
        XCTAssertEqual(effects.count,0)
        for _ in 0..<1000 { effects.append(try GraphicEffect.decode(packet()),at:0) }
        XCTAssertEqual(effects.count,128)
        effects.expire(at:1); XCTAssertEqual(effects.count,0)
    }
}
