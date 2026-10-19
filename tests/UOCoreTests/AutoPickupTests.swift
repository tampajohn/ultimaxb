import XCTest
@testable import UOCore
final class AutoPickupTests:XCTestCase {
    func item(_ serial:UInt32=0x40000001,graphic:Int=0xF7A,x:Int=10,flags:UInt8=0)->GroundItem {
        GroundItem(serial:serial,graphic:graphic,amount:2,x:x,y:10,z:0,direction:0,hue:0,flags:flags)
    }
    func testEligibilityAndConfirmation() {
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        var gather=AutoPickup(); gather.mode = .reagents
        XCTAssertNil(gather.select(items:[item(x:12),item(graphic:0xF5E)],player:player,at:0))
        let herb=item(); XCTAssertEqual(gather.select(items:[herb],player:player,at:0)?.serial,herb.serial)
        gather.begin(herb,bag:0x40000002,contents:[],at:0)
        XCTAssertNil(gather.select(items:[item(0x40000003)],player:player,at:1))
        let received=ContainerItem(serial:herb.serial,graphic:herb.graphic,amount:2,x:0,y:0,container:0x40000002,hue:0)
        gather.update(contents:[received],at:1); XCTAssertNotNil(gather.pending)
        gather.receive(Data([0x29])); gather.update(contents:[received],at:1.1); XCTAssertNil(gather.pending)
        XCTAssertNil(gather.select(items:[herb],player:player,at:2))
    }
    func testTimeoutRefusalAndMovableFilter() {
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0)
        var gather=AutoPickup(); gather.mode = .all
        XCTAssertNotNil(gather.select(items:[item(graphic:0xF5E)],player:player,at:0))
        XCTAssertNil(gather.select(items:[item(graphic:0xF5E)],player:player,at:0,portable:{_ in false}))
        XCTAssertNotNil(gather.select(items:[item(graphic:0xF5E,flags:0x20)],player:player,at:0))
        gather.begin(item(),bag:2,contents:[],at:0); gather.update(contents:[],at:5)
        XCTAssertEqual(gather.mode,.off); XCTAssertNil(gather.pending)
        gather.mode = .reagents; gather.begin(item(),bag:2,contents:[],at:6)
        gather.receive(Data([0x27,0])); XCTAssertEqual(gather.mode,.reagents)
        XCTAssertNil(gather.pending)
        XCTAssertNil(gather.select(items:[item()],player:player,at:10))
        XCTAssertEqual(gather.select(items:[item(99)],player:player,at:10)?.serial,99)
    }
    func testMergedStackNeedsAcknowledgementAndExactQuantity() {
        var gather=AutoPickup(); gather.mode = .reagents
        let before=ContainerItem(serial:9,graphic:0xF7A,amount:10,x:0,y:0,container:2,hue:0)
        gather.begin(item(),bag:2,contents:[before],at:0); gather.receive(Data([0x29]))
        gather.update(contents:[before],at:1); XCTAssertNotNil(gather.pending)
        let after=ContainerItem(serial:9,graphic:0xF7A,amount:12,x:0,y:0,container:2,hue:0)
        gather.update(contents:[after],at:2); XCTAssertNil(gather.pending)
    }
}
