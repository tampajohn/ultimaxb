import XCTest
@testable import UOCore

final class ManualInventoryTransferTests:XCTestCase {
    func item(_ serial:UInt32=4,amount:Int=10,bag:UInt32=2,x:Int=10)->Data {
        Data([0x25])+Data(LoginPackets.seed(serial))+Data([0x0E,0xED,0,UInt8(amount>>8),UInt8(amount&255),0,UInt8(x),0,10])+Data(LoginPackets.seed(bag))+Data([0,0])
    }
    func equip()->Data { Data([0x2E])+Data(LoginPackets.seed(4))+Data([0x0E,0xED,0,1,0,0,0,1,0,0]) }
    func testMoveWaitsForPlacementNotRemovalOrUnrelatedUpdate() throws {
        var world=WorldState(); try world.apply(item())
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:4,amount:10,destination:.container(3,x:20,y:10),world:world,time:0)
        let remove=Data([0x1D])+Data(LoginPackets.seed(4)); try world.apply(remove)
        XCTAssertNil(transfer.receive(remove,world:world))
        let unrelated=item(9,amount:1,bag:3); try world.apply(unrelated)
        XCTAssertNil(transfer.receive(unrelated,world:world))
        let placed=item(bag:3,x:20); try world.apply(placed)
        XCTAssertEqual(transfer.receive(placed,world:world),.placed)
        XCTAssertNil(transfer.serial)
        XCTAssertNil(transfer.receive(placed,world:world))
    }
    func testSplitInSameBagRequiresNewStackNotRemainder() throws {
        var world=WorldState(); try world.apply(item())
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:4,amount:5,destination:.container(2,x:20,y:10),world:world,time:0)
        let remainder=item(amount:5); try world.apply(remainder)
        XCTAssertNil(transfer.receive(remainder,world:world))
        let newStack=item(5,amount:5,x:20); try world.apply(newStack)
        XCTAssertEqual(transfer.receive(newStack,world:world),.placed)
    }
    func testMergeUsesIncreaseNotPreexistingDestinationQuantity() throws {
        var world=WorldState(); try world.apply(item()); try world.apply(item(5,amount:50,bag:3))
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:4,amount:10,destination:.container(3,x:0xFFFF,y:0xFFFF),world:world,time:0)
        XCTAssertNil(transfer.receive(item(5,amount:50,bag:3),world:world))
        let merged=item(5,amount:60,bag:3); try world.apply(merged)
        XCTAssertEqual(transfer.receive(merged,world:world),.placed)
    }
    func testRearrangeAndNoOpFullStackPlacement() throws {
        var world=WorldState(); try world.apply(item())
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:4,amount:10,destination:.container(2,x:10,y:10),world:world,time:0)
        XCTAssertEqual(transfer.receive(item(),world:world),.placed)
    }
    func testEquipThenUnequip() throws {
        var world=WorldState(); try world.apply(item(amount:1))
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:4,amount:1,destination:.equipment(1,1),world:world,time:0)
        try world.apply(equip()); XCTAssertEqual(transfer.receive(equip(),world:world),.placed)
        transfer.begin(serial:4,amount:1,destination:.container(2,x:0xFFFF,y:0xFFFF),world:world,time:1)
        let placed=item(amount:1); try world.apply(placed)
        XCTAssertEqual(transfer.receive(placed,world:world),.placed)
    }
    func testDropOntoExistingStackSerial() throws {
        var world=WorldState(); try world.apply(item()); try world.apply(item(5,amount:50,bag:3))
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:4,amount:10,destination:.container(5,x:0,y:0),world:world,time:0)
        let merged=item(5,amount:60,bag:3); try world.apply(merged)
        XCTAssertEqual(transfer.receive(merged,world:world),.placed)
    }
    func testGroundDropChecksCoordinates() throws {
        var world=WorldState(); try world.apply(item(0x40000004))
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:0x40000004,amount:10,destination:.ground(20,30,0),world:world,time:0)
        let wrong=Data([0x1A,0,16,0xC0,0,0,4,0x0E,0xED,0,10,0,19,0,30,0])
        try world.apply(wrong); XCTAssertNil(transfer.receive(wrong,world:world))
        var right=wrong; right[12]=20
        try world.apply(right); XCTAssertEqual(transfer.receive(right,world:world),.placed)
    }
    func testRefusalAndTimeoutAreTerminalWithoutRetry() throws {
        var world=WorldState(); try world.apply(item())
        var transfer=ManualInventoryTransfer()
        transfer.begin(serial:4,amount:10,destination:.container(3,x:0,y:0),world:world,time:10)
        XCTAssertNil(transfer.poll(time:14.99))
        XCTAssertEqual(transfer.poll(time:15),.timedOut)
        XCTAssertNil(transfer.poll(time:20))
        transfer.begin(serial:4,amount:10,destination:.container(3,x:0,y:0),world:world,time:30)
        XCTAssertEqual(transfer.receive(Data([0x27,255]),world:world),.refused)
        XCTAssertNil(transfer.serial)
    }
}
