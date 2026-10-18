import XCTest
@testable import UOCore
final class OreHaulTests:XCTestCase {
    let origin = WalkPoint(x:10,y:10,z:0),next = WalkPoint(x:11,y:10,z:0)
    let ore = ContainerItem(serial:22,graphic:0x19B9,amount:100,x:0,y:0,container:23,hue:0)
    var held:OreHaul.Location { .backpack(container:23,amount:100,graphic:0x19B9,hue:0) }
    func ground(_ point:WalkPoint)->OreHaul.Location { .ground(point:point,amount:100,graphic:0x19B9,hue:0) }
    func testConfirmedCycleAndReorderedAcknowledgements() throws {
        var haul = OreHaul()
        XCTAssertEqual(try haul.start(ore:ore,player:origin,route:[next],at:0),.drop(serial:22,amount:100,at:origin))
        XCTAssertNil(haul.update(location:ground(origin),player:origin,movementSettled:true,at:1))
        haul.acknowledgeTransfer()
        XCTAssertEqual(haul.update(location:ground(origin),player:origin,movementSettled:true,at:2),.walk(next))
        XCTAssertNil(haul.update(location:ground(origin),player:next,movementSettled:false,at:3))
        XCTAssertEqual(haul.update(location:ground(origin),player:next,movementSettled:true,at:4),.pickup(serial:22,amount:100,backpack:23))
        haul.acknowledgeTransfer()
        XCTAssertNil(haul.update(location:.unknown,player:next,movementSettled:true,at:5))
        XCTAssertEqual(haul.state,.waitingForPickup)
        XCTAssertNil(haul.update(location:held,player:next,movementSettled:true,at:6))
        XCTAssertEqual(haul.state,.completed); XCTAssertNil(haul.recoveryLocation)
    }
    func testNextStepDoesNotDropUntilPickupConfirmed() throws {
        var haul = OreHaul()
        _ = try haul.start(ore:ore,player:origin,route:[next,WalkPoint(x:12,y:10,z:0)],at:0)
        haul.acknowledgeTransfer()
        XCTAssertNil(haul.update(location:held,player:origin,movementSettled:true,at:1))
        _ = haul.update(location:ground(origin),player:origin,movementSettled:true,at:2)
        _ = haul.update(location:ground(origin),player:next,movementSettled:true,at:3)
        XCTAssertNil(haul.update(location:held,player:next,movementSettled:true,at:4))
        haul.acknowledgeTransfer()
        XCTAssertEqual(haul.update(location:held,player:next,movementSettled:true,at:5),.drop(serial:22,amount:100,at:next))
    }
    func testStopAndTimeoutPreserveRecoveryLocation() throws {
        for reason in [OreHaul.StopReason.cancelled,.disconnected,.refused] {
            var haul = OreHaul()
            _ = try haul.start(ore:ore,player:origin,route:[next],at:0)
            _ = haul.update(location:ground(origin),player:origin,movementSettled:true,at:1)
            haul.stop(reason); haul.acknowledgeTransfer()
            XCTAssertNil(haul.update(location:ground(origin),player:origin,movementSettled:true,at:2))
            XCTAssertEqual(haul.state,.stopped(reason)); XCTAssertEqual(haul.recoveryLocation,origin)
        }
        var haul = OreHaul()
        _ = try haul.start(ore:ore,player:origin,route:[next],at:0)
        XCTAssertNil(haul.update(location:ground(origin),player:origin,movementSettled:true,at:10))
        XCTAssertEqual(haul.state,.stopped(.timeout)); XCTAssertEqual(haul.recoveryLocation,origin)
    }
    func testLateDropAfterStopStillRecordsRecovery() throws {
        var haul = OreHaul()
        _ = try haul.start(ore:ore,player:origin,route:[next],at:0)
        haul.stop()
        XCTAssertNil(haul.update(location:ground(origin),player:origin,movementSettled:true,at:1))
        XCTAssertEqual(haul.recoveryLocation,origin)
        XCTAssertEqual(haul.state,.stopped(.cancelled))
        XCTAssertNil(haul.update(location:held,player:origin,movementSettled:true,at:2))
        XCTAssertNil(haul.recoveryLocation)
    }
    func testChangedStackAndInvalidRouteNeverMove() throws {
        var haul = OreHaul()
        _ = try haul.start(ore:ore,player:origin,route:[next],at:0)
        haul.acknowledgeTransfer()
        XCTAssertNil(haul.update(location:.ground(point:origin,amount:99,graphic:0x19B9,hue:0),player:origin,movementSettled:true,at:1))
        XCTAssertEqual(haul.state,.stopped(.oreChanged))
        haul = OreHaul()
        XCTAssertThrowsError(try haul.start(ore:ore,player:origin,route:[WalkPoint(x:15,y:10,z:0)],at:0))
        let sword = ContainerItem(serial:22,graphic:0xF5E,amount:1,x:0,y:0,container:23,hue:0)
        XCTAssertThrowsError(try haul.start(ore:sword,player:origin,route:[next],at:0))
    }
}
