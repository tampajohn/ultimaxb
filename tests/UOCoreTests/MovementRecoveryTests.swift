import XCTest
@testable import UOCore

final class MovementRecoveryTests:XCTestCase {
    private let player=WorldMobile(serial:1,body:400,x:100,y:100,z:0,direction:2)
    func testMissingSyncRepliesRetryThenRemainBlockedUntilAuthoritativeUpdate() throws {
        var movement=PlayerMovement()
        _ = movement.request(direction:2,player:player,at:0)
        XCTAssertEqual(movement.poll(at:2),PlayerMovement.requestPosition)
        XCTAssertNil(movement.poll(at:3.9))
        XCTAssertEqual(movement.poll(at:4),PlayerMovement.requestPosition)
        XCTAssertEqual(movement.poll(at:6),PlayerMovement.requestPosition)
        XCTAssertNil(movement.poll(at:8))
        XCTAssertTrue(movement.positionSyncTimedOut)
        XCTAssertNil(movement.poll(at:100))
        XCTAssertNil(movement.request(direction:2,player:player,at:100))
        XCTAssertEqual(movement.pendingCount,1,"Timeout must not invent acknowledgements")
        _ = try movement.receive(Data([0x20])+Data(repeating:0,count:18),player:player)
        XCTAssertFalse(movement.positionSyncTimedOut)
        XCTAssertFalse(movement.awaitingPosition)
        XCTAssertNotNil(movement.request(direction:2,player:player,at:101))
    }
    func testDeniedMovementStartsOneTrackedRecoveryRequest() throws {
        var movement=PlayerMovement()
        _ = movement.request(direction:2,player:player,at:0)
        _ = try movement.receive(Data([0x21,0,0,100,0,100,2,0]),player:player)
        XCTAssertEqual(movement.resynchronize(at:1),PlayerMovement.requestPosition)
        XCTAssertNil(movement.poll(at:2))
        XCTAssertEqual(movement.poll(at:3),PlayerMovement.requestPosition)
        _ = try movement.receive(Data([0x20])+Data(repeating:0,count:18),player:player)
        XCTAssertNil(movement.poll(at:5))
        XCTAssertFalse(movement.positionSyncTimedOut)
    }
    func testLateStepAcknowledgementCannotReleasePositionRecovery() throws {
        var movement=PlayerMovement()
        _ = movement.request(direction:2,player:player,at:0)
        _ = movement.poll(at:2)
        _ = try movement.receive(Data([0x22,0,1]),player:player)
        XCTAssertTrue(movement.awaitingPosition)
        XCTAssertNil(movement.request(direction:2,player:player,at:3))
        XCTAssertEqual(movement.poll(at:4),PlayerMovement.requestPosition)
    }
}
