import XCTest
@testable import UOCore
final class AutoPickupTests:XCTestCase {
    func item(_ serial:UInt32=0x40000001,graphic:Int=0xF7A,x:Int=10,flags:UInt8=0)->GroundItem {
        GroundItem(serial:serial,graphic:graphic,amount:2,x:x,y:10,z:0,direction:0,hue:0,flags:flags)
    }
    func testDetourRadiusRespectsEligibilityAndNearestFirst() {
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        var gather=AutoPickup(); gather.mode = .reagents
        let far=item(1,x:16),near=item(9,x:12)
        XCTAssertNil(gather.select(items:[far,near],player:player,at:0))
        XCTAssertEqual(gather.select(items:[far,near,item(2,graphic:0xF5E,x:11)],player:player,at:0,radius:6)?.serial,9)
        gather.skip(9)
        XCTAssertEqual(gather.select(items:[far,near],player:player,at:0,radius:6)?.serial,1)
        XCTAssertNil(gather.select(items:[item(x:17)],player:player,at:0,radius:100))
    }
    func testTwoTilePickupAndMultipleCandidates() {
        var gather=AutoPickup(); gather.mode = .reagents
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        let near=item(8,x:12),far=item(9,x:13)
        XCTAssertEqual(gather.select(items:[far,near],player:player,at:0,radius:AutoPickup.reach)?.serial,8)
        XCTAssertEqual(gather.candidates(items:[far,near],player:player,at:0,radius:6).map(\.serial),[8,9])
        gather.skip(8)
        XCTAssertNil(gather.select(items:[far,near],player:player,at:0,radius:AutoPickup.reach))
        XCTAssertEqual(gather.candidates(items:[far,near],player:player,at:0,radius:6).map(\.serial),[9])
    }
    func testEligibilityAndConfirmation() {
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        var gather=AutoPickup(); gather.mode = .reagents
        XCTAssertNil(gather.select(items:[item(x:12),item(graphic:0xF5E)],player:player,at:0))
        let herb=item(); XCTAssertEqual(gather.select(items:[herb],player:player,at:0)?.serial,herb.serial)
        gather.begin(herb,bag:0x40000002,contents:[],at:0)
        XCTAssertNil(gather.select(items:[item(0x40000003)],player:player,at:1))
        let received=ContainerItem(serial:herb.serial,graphic:herb.graphic,amount:2,x:0,y:0,container:0x40000002,hue:0)
        gather.update(contents:[received],at:1); XCTAssertNil(gather.pending)
        XCTAssertEqual(gather.gathered.credits[herb.serial]?.amount,2)
        XCTAssertEqual(gather.mode,.reagents)
        gather.receive(Data([0x29])); gather.update(contents:[received],at:1.1); XCTAssertNil(gather.pending)
        XCTAssertEqual(gather.gathered.credits[herb.serial]?.amount,2,"Late acknowledgement must not double-count goods")
        XCTAssertNil(gather.select(items:[herb],player:player,at:2))
    }
    func testUnmarkedFurnitureIsNotAutomaticLootOrADetour() {
        var gather=AutoPickup(); gather.mode = .all
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        XCTAssertNil(gather.select(items:[item(graphic:0xB2C)],player:player,at:0))
        XCTAssertNil(gather.select(items:[item(graphic:0xB2C,x:14)],player:player,at:0,radius:6))
        XCTAssertNotNil(gather.select(items:[item(graphic:0xEED)],player:player,at:0))
        XCTAssertNotNil(gather.select(items:[item(graphic:0xF5E,flags:0x20)],player:player,at:0))
    }
    func testTimeoutRefusalAndMovableFilter() {
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        var gather=AutoPickup(); gather.mode = .all
        XCTAssertNil(gather.select(items:[item(graphic:0xF5E)],player:player,at:0))
        XCTAssertNil(gather.select(items:[item(graphic:0xF5E)],player:player,at:0,portable:{_ in false}))
        XCTAssertNotNil(gather.select(items:[item(graphic:0xF5E,flags:0x20)],player:player,at:0))
        gather.begin(item(),bag:2,contents:[],at:0); gather.update(contents:[],at:5)
        XCTAssertEqual(gather.mode,.off); XCTAssertNil(gather.pending)
        XCTAssertTrue(gather.gathered.credits.isEmpty)
        gather.mode = .reagents; gather.begin(item(),bag:2,contents:[],at:6)
        gather.receive(Data([0x27,0])); XCTAssertEqual(gather.mode,.reagents)
        XCTAssertNil(gather.pending)
        XCTAssertTrue(gather.gathered.credits.isEmpty)
        XCTAssertNil(gather.select(items:[item()],player:player,at:10))
        XCTAssertEqual(gather.select(items:[item(99)],player:player,at:10)?.serial,99)
    }
    func testMergedStackConfirmsWithoutSeparateAcknowledgement() {
        var gather=AutoPickup(); gather.mode = .reagents
        let before=ContainerItem(serial:9,graphic:0xF7A,amount:10,x:0,y:0,container:2,hue:0)
        gather.begin(item(),bag:2,contents:[before],at:0)
        gather.update(contents:[before],at:1); XCTAssertNotNil(gather.pending)
        let after=ContainerItem(serial:9,graphic:0xF7A,amount:12,x:0,y:0,container:2,hue:0)
        gather.update(contents:[after],at:2); XCTAssertNil(gather.pending)
        XCTAssertEqual(gather.gathered.credits[9]?.amount,2,"The original ten herbs are not gathered goods")
        XCTAssertEqual(gather.mode,.reagents)
    }
}
