import XCTest
@testable import UOCore

final class RouteRecoveryTests:XCTestCase {
    func testUnlocatedRejectionsHaveBoundedRetriesWithoutInventingWalls() {
        var recovery=RouteRecovery()
        let origin=WalkPoint(x:10,y:10,z:0)
        for index in 0..<3 {
            XCTAssertTrue(recovery.rejectWithoutStep(from:origin,at:Double(index)))
            XCTAssertEqual(recovery.retryAt,Double(index)+0.25)
            XCTAssertTrue(recovery.blocked.isEmpty)
        }
        XCTAssertFalse(recovery.rejectWithoutStep(from:origin,at:4))
        recovery.progress(WalkPoint(x:18,y:10,z:0))
        XCTAssertTrue(recovery.rejectWithoutStep(from:origin,at:5))
    }
    func testDeniedTurnAndUnknownSequenceDoNotIdentifyAnObstacle() throws {
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0,direction:0)
        for sequence:UInt8 in [0,99] {
            var movement=PlayerMovement()
            XCTAssertNotNil(movement.request(direction:2,player:player,at:0))
            let correction=try movement.receive(Data([0x21,sequence,0,10,0,10,2,0]),player:player)
            XCTAssertEqual(correction?.x,10)
            XCTAssertNil(movement.rejectedStep)
            XCTAssertTrue(movement.awaitingPosition)
            XCTAssertNil(movement.request(direction:2,player:player,at:1))
        }
    }
    func testAnimalsExpireWithoutSpendingWallRetryBudget() {
        var recovery=RouteRecovery()
        let origin=WalkPoint(x:10,y:10,z:0), animal=WalkPoint(x:11,y:10,z:0)
        for index in 0..<12 {
            let time=Double(index)*3
            XCTAssertTrue(recovery.reject(animal,from:origin,temporary:true,at:time))
            XCTAssertEqual(recovery.attempts,0)
            XCTAssertTrue(recovery.blocked.contains(animal))
            XCTAssertEqual(recovery.retryAt,time+0.75)
            recovery.expire(at:time+2)
            XCTAssertFalse(recovery.blocked.contains(animal))
        }
        XCTAssertFalse(recovery.reject(animal,from:origin,temporary:true,at:40))
        recovery.progress(WalkPoint(x:18,y:10,z:0))
        XCTAssertTrue(recovery.reject(animal,from:origin,temporary:true,at:41))
    }
    func testRepeatedLocalFailuresRemainBounded() {
        var recovery=RouteRecovery()
        let origin=WalkPoint(x:10,y:10,z:0)
        for x in 11...13 { XCTAssertTrue(recovery.reject(WalkPoint(x:x,y:10,z:0),from:origin)) }
        // Turning, elevation updates, or circling within the same area are not
        // enough progress to endlessly retry an impassable obstruction.
        for point in [origin,WalkPoint(x:12,y:12,z:20),origin] { recovery.progress(point) }
        XCTAssertFalse(recovery.reject(WalkPoint(x:14,y:10,z:0),from:origin))
        XCTAssertEqual(recovery.attempts,3)
    }
    func testProgressRenewsBudgetAndPrunesDistantObstacles() {
        var recovery=RouteRecovery()
        let origin=WalkPoint(x:10,y:10,z:0)
        XCTAssertTrue(recovery.reject(WalkPoint(x:11,y:10,z:0),from:origin))
        recovery.progress(WalkPoint(x:18,y:10,z:0))
        XCTAssertEqual(recovery.attempts,0)
        XCTAssertEqual(recovery.blocked.count,1)
        XCTAssertTrue(recovery.reject(WalkPoint(x:19,y:10,z:0),from:WalkPoint(x:18,y:10,z:0)))
        recovery.progress(WalkPoint(x:80,y:10,z:0))
        XCTAssertTrue(recovery.blocked.isEmpty)
        XCTAssertEqual(recovery.attempts,0)
    }
    func testAcknowledgementDoesNotCreditQueuedPredictionOrTurn() throws {
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0,direction:2,hue:0,flags:0,notoriety:1)
        var movement=PlayerMovement()
        XCTAssertNotNil(movement.request(direction:2,player:player,at:0))
        let first=try XCTUnwrap(movement.predictedPosition)
        XCTAssertNotNil(movement.request(direction:2,player:first,at:0.4))
        let latest=try XCTUnwrap(movement.predictedPosition)
        _ = try movement.receive(Data([0x22,0,1]),player:latest)
        XCTAssertEqual(movement.acknowledgedStep,WalkPoint(x:11,y:10,z:0))
        _ = try movement.receive(Data([0x22,0,1]),player:latest)
        XCTAssertNil(movement.acknowledgedStep) // duplicate acknowledgement
        var turn=PlayerMovement()
        XCTAssertNotNil(turn.request(direction:4,player:player,at:0))
        _ = try turn.receive(Data([0x22,0,1]),player:player)
        XCTAssertNil(turn.acknowledgedStep)
    }
}
