import XCTest
@testable import UOCore

final class MobileDeathTests:XCTestCase {
    let packet = Data([0xAF,0,0,0,1,0x40,0,0,2,0,0,0,1])
    func testFramingAndAtomicRemoval() throws {
        for split in 0...packet.count {
            var framer = GamePacketFramer()
            let frames = try framer.receive(Data(packet.prefix(split))) + framer.receive(Data(packet.dropFirst(split)))
            XCTAssertEqual(frames,[packet])
        }
        let event = try MobileDeath.decode(packet)
        XCTAssertEqual(event.serial,1); XCTAssertEqual(event.corpse,0x40000002); XCTAssertTrue(event.alternate)
        var world = WorldState(), target = CombatTarget()
        try world.apply(Data([0x77,0,0,0,1,1,0x90,0,10,0,10,0,3,0,0,0,1]))
        try world.apply(Data([0x2E,0x40,0,0,3,0x13,0xB9,0,1,0,0,0,1,0,0]))
        try target.apply(Data([0xAA,0,0,0,1]))
        for bad in [Data(packet.dropLast()),Data([0xAF])+Data(repeating:0,count:12)] {
            XCTAssertThrowsError(try world.apply(bad))
            XCTAssertThrowsError(try target.apply(bad))
            XCTAssertNotNil(world.mobiles[1]); XCTAssertNotNil(world.equipment[0x40000003]); XCTAssertEqual(target.serial,1)
        }
        XCTAssertTrue(try world.apply(packet)); XCTAssertTrue(try target.apply(packet))
        XCTAssertNil(world.mobiles[1]); XCTAssertNil(world.equipment[0x40000003]); XCTAssertNil(target.serial)
        XCTAssertFalse(try world.apply(packet)); XCTAssertFalse(try target.apply(packet))
    }
    func testVisualSnapshotExpiresAndDoesNotFollowResurrection() throws {
        let event = try MobileDeath.decode(packet)
        let mobile = WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        let clothes = [EquippedItem(serial:0x40000003,graphic:0x13B9,layer:1,owner:1)]
        let pose = MobilePresentation(x:9.5,y:10,z:1.5,walking:true,frame:3)
        var deaths = DeathAnimations()
        deaths.play(event,mobile:mobile,equipment:clothes,pose:pose,frames:5,at:10)
        XCTAssertEqual(deaths.mobiles.count,1)
        XCTAssertEqual(deaths.mobiles[0].serial,0x80000001)
        XCTAssertEqual(deaths.equipment[0].owner,0x80000001)
        XCTAssertEqual(deaths.hiddenCorpses,[0x40000002])
        XCTAssertTrue(deaths.hides(mobile))
        XCTAssertFalse(deaths.hides(WorldMobile(serial:1,body:402,x:10,y:10,z:0)))
        let first = try XCTUnwrap(deaths.presentations(at:10)[0x80000001])
        XCTAssertEqual(first.x,9.5); XCTAssertEqual(first.z,1.5); XCTAssertEqual(first.action,22); XCTAssertFalse(first.walking)
        XCTAssertEqual(deaths.presentations(at:10.31)[0x80000001]?.frame,3)
        deaths.play(event,mobile:mobile,equipment:[],pose:nil,frames:5,at:10.2)
        deaths.expire(at:10.5)
        XCTAssertFalse(deaths.isAnimating); XCTAssertTrue(deaths.hiddenCorpses.isEmpty)
        XCTAssertTrue(deaths.mobiles.isEmpty); XCTAssertTrue(deaths.equipment.isEmpty)
        deaths.play(event,mobile:mobile,equipment:clothes,pose:nil,frames:0,at:11)
        XCTAssertFalse(deaths.isAnimating)
    }
    func testClassicDeathGroupsAndNoCorpse() throws {
        for (body,normal,alternate) in [(1,2,3),(200,8,12),(400,21,22)] {
            XCTAssertEqual(CorpseArt.deathAction(body:body),normal)
            XCTAssertEqual(CorpseArt.deathAction(body:body,alternate:true),alternate)
        }
        var noCorpse = packet
        noCorpse.replaceSubrange(5..<9,with:[0,0,0,0])
        XCTAssertEqual(try MobileDeath.decode(noCorpse).corpse,0)
    }
}
