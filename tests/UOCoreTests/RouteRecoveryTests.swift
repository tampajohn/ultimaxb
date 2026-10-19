import XCTest
@testable import UOCore

final class RouteRecoveryTests:XCTestCase {
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
