import XCTest
@testable import UOCore

final class GraphicEffectTests: XCTestCase {
    private func packet(kind:UInt8 = 3, duration:UInt8 = 20) -> Data {
        Data([0x70,kind,0,0,0,1,0,0,0,2,0x37,0x6A,
              0x09,0xC4,0x01,0xF4,0xFB,0x09,0xC5,0x01,0xF5,0x80,5,duration,0,0,1,0])
    }
    func testExtendedEffectsAndFragmentedFraming() throws {
        var colored = packet(); colored[0] = 0xC0
        colored += Data([0,0,0,33,0,0,0,9])
        var particle = colored; particle[0] = 0xC7
        particle += Data(repeating:0,count:13)
        for bytes in [colored,particle] {
            let effect = try GraphicEffect.decode(bytes)
            XCTAssertEqual(effect.hue,33); XCTAssertEqual(effect.blendMode,2)
            for n in 0..<bytes.count { XCTAssertThrowsError(try GraphicEffect.decode(bytes.prefix(n))) }
            XCTAssertThrowsError(try GraphicEffect.decode(bytes+Data([0])))
            var world = WorldEffects(); world.append(effect,at:0)
            let tile = world.tiles(at:0,mobiles:[],items:[]).first
            XCTAssertEqual(tile?.hue,33); XCTAssertEqual(tile?.effectBlendMode,2)
        }
        var framer = GamePacketFramer()
        let stream = colored + particle + packet()
        var received:[Data] = []
        for byte in stream { received += try framer.receive(Data([byte])) }
        XCTAssertEqual(received,[colored,particle,packet()])
        XCTAssertThrowsError(try framer.receive(Data([0xC1])))
    }
    func testBlendFactorsClampAndPreserveTransparentPixels() {
        let expected:[UInt8] = [100,78,255,255,78,156,82]
        for mode in UInt32(0)...6 {
            XCTAssertEqual(EffectBlend.channel(source:100,destination:200,alpha:255,mode:mode),expected[Int(mode)])
            XCTAssertEqual(EffectBlend.channel(source:100,destination:200,alpha:0,mode:mode),200)
        }
        XCTAssertEqual(EffectBlend.channel(source:255,destination:20,alpha:255,mode:6),0)
        XCTAssertEqual(EffectBlend.channel(source:200,destination:200,alpha:255,mode:5),255)
        XCTAssertEqual(EffectBlend.channel(source:100,destination:200,alpha:128,mode:0),149)
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
        var effects = WorldEffects()
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
    func testLightningUsesGumpFramesAndFixedLifetime() throws {
        var effects = WorldEffects()
        var bytes = packet(kind:1,duration:0)
        bytes[10] = 0; bytes[11] = 0 // Lightning commonly has no static-art graphic.
        effects.append(try GraphicEffect.decode(bytes),at:0)
        let mobile = WorldMobile(serial:1,body:400,x:2500,y:500,z:0)
        let first = effects.tiles(at:0,mobiles:[mobile],items:[])
        XCTAssertEqual(first.first?.effectGump,0x4E20)
        XCTAssertEqual(first.first?.effectYOffset,-3)
        XCTAssertEqual(effects.tiles(at:0.11,mobiles:[mobile],items:[]).first?.effectGump,0x4E22)
        XCTAssertTrue(effects.tiles(at:0.2,mobiles:[],items:[]).isEmpty)
        XCTAssertTrue(effects.tiles(at:0.4,mobiles:[mobile],items:[]).isEmpty)
        XCTAssertEqual(effects.count,0)
    }
    func testProjectileTravelImpactAndExpiry() throws {
        var bytes = packet(kind:0,duration:0)
        bytes[10] = 0x36; bytes[11] = 0xD4
        bytes[21] = 0xFB // Same destination elevation as source.
        bytes[22] = 1 // 250 screen pixels per second.
        bytes[26] = 0; bytes[27] = 1
        var effects = WorldEffects()
        effects.append(try GraphicEffect.decode(bytes),at:0)
        let first = effects.tiles(at:0,mobiles:[],items:[])
        XCTAssertEqual(first.first?.effectPose?.x,2500)
        XCTAssertNotNil(first.first?.effectRotation)
        let midpoint = effects.tiles(at:0.08,mobiles:[],items:[])
        XCTAssertGreaterThan(midpoint[0].effectPose!.x,2500)
        XCTAssertLessThan(midpoint[0].effectPose!.x,2501)
        let impact = effects.tiles(at:0.2,mobiles:[],items:[])
        XCTAssertEqual(impact.first?.art,0x4000+0x36CB)
        XCTAssertEqual(impact.first?.effectPose?.x,2501)
        XCTAssertNil(impact.first?.effectRotation)
        XCTAssertTrue(effects.tiles(at:0.61,mobiles:[],items:[]).isEmpty)
        bytes[27] = 0
        effects.append(try GraphicEffect.decode(bytes),at:1)
        XCTAssertTrue(effects.tiles(at:2,mobiles:[],items:[]).isEmpty)
        XCTAssertEqual(effects.count,0)
    }
    func testProjectileTracksTargetAndHasTimeout() throws {
        var effects = WorldEffects()
        effects.append(try GraphicEffect.decode(packet(kind:0)),at:0)
        let target = WorldMobile(serial:2,body:400,x:2600,y:600,z:20)
        _ = effects.tiles(at:0,mobiles:[target],items:[])
        let moving = effects.tiles(at:0.01,mobiles:[target],items:[])
        XCTAssertLessThan(moving[0].effectPose!.x,2600)
        XCTAssertGreaterThan(moving[0].effectPose!.x,2500)
        XCTAssertTrue(effects.tiles(at:10,mobiles:[target],items:[]).isEmpty)
    }
    func testProjectileRotationPreservesArtAndTransparency() {
        let art = Sprite(width:2,height:1,rgba:[255,0,0,255,0,255,0,255])
        XCTAssertEqual(EffectRotation.rotate(art,radians:0).sprite.rgba,art.rgba)
        let rotated = EffectRotation.rotate(art,radians:Double.pi)
        let opaque = stride(from:0,to:rotated.sprite.rgba.count,by:4).filter { rotated.sprite.rgba[$0+3] != 0 }
        XCTAssertEqual(opaque.count,2)
        XCTAssertEqual(opaque.map { rotated.sprite.rgba[$0+1] },[255,0])
    }
    func testBoundedStateAndUnsupportedKinds() throws {
        var effects = WorldEffects()
        for kind:UInt8 in [4] { effects.append(try GraphicEffect.decode(packet(kind:kind)),at:0) }
        effects.append(try GraphicEffect.decode(packet(duration:0)),at:0)
        XCTAssertEqual(effects.count,0)
        for _ in 0..<1000 { effects.append(try GraphicEffect.decode(packet()),at:0) }
        XCTAssertEqual(effects.count,128)
        effects.expire(at:1); XCTAssertEqual(effects.count,0)
    }
}
