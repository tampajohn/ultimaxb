import XCTest
@testable import UOCore
final class GatheredDropTests:XCTestCase {
    let point=WalkPoint(x:10,y:11,z:3)
    func bag(_ amount:Int)->ContainerItem { ContainerItem(serial:1,graphic:0xF7A,amount:amount,x:0,y:0,container:2,hue:0) }
    func ground(_ amount:Int,x:Int=10)->GroundItem {
        GroundItem(serial:99,graphic:0xF7A,amount:amount,x:x,y:11,z:3,direction:0,hue:0,flags:0)
    }
    func drop()->GatheredDrop {
        var ledger=GatheredInventory()
        ledger.confirm(graphic:0xF7A,hue:0,amount:4,bag:2,before:[bag(10)],after:[bag(14)])
        return GatheredDrop(credit:ledger.credits[1]!,amount:3,point:point,contents:[bag(14)],ground:[ground(2)],at:0)
    }
    func testRequiresBothInventoryReductionAndGroundIncrease() {
        let transfer=drop()
        XCTAssertEqual(transfer.result(contents:[bag(11)],ground:[ground(2)],at:1),.waiting)
        XCTAssertEqual(transfer.result(contents:[bag(14)],ground:[ground(5)],at:1),.waiting)
        XCTAssertEqual(transfer.result(contents:[bag(11)],ground:[ground(5,x:12)],at:1),.waiting)
        XCTAssertEqual(transfer.result(contents:[bag(11)],ground:[ground(5)],at:1),.confirmed)
    }
    func testRefusalTimeoutAndAcknowledgementAreNotSuccess() {
        var transfer=drop()
        transfer.receive(Data([0x29]))
        XCTAssertEqual(transfer.result(contents:[bag(14)],ground:[],at:1),.waiting)
        XCTAssertEqual(transfer.result(contents:[bag(14)],ground:[],at:5),.timedOut)
        transfer.receive(Data([0x27,0]))
        XCTAssertEqual(transfer.result(contents:[bag(11)],ground:[ground(5)],at:2),.refused)
    }
}
