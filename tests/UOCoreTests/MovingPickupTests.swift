import XCTest
@testable import UOCore
final class MovingPickupTests:XCTestCase {
    func testReachMustIncludeUnacknowledgedOriginAndDestination() {
        var movement=PlayerMovement()
        let player=WorldMobile(serial:1,body:400,x:10,y:10,z:0,direction:2)
        XCTAssertNotNil(movement.request(direction:2,player:player,at:0))
        let predicted=movement.predictedPosition!
        XCTAssertTrue(movement.canPickUp(at:WalkPoint(x:12,y:10,z:0),player:predicted))
        XCTAssertFalse(movement.canPickUp(at:WalkPoint(x:13,y:10,z:0),player:predicted))
        XCTAssertFalse(movement.canPickUp(at:WalkPoint(x:8,y:10,z:0),player:predicted))
        XCTAssertFalse(movement.canPickUp(at:WalkPoint(x:11,y:10,z:17),player:predicted))
        _=movement.resynchronize(at:1)
        XCTAssertFalse(movement.canPickUp(at:WalkPoint(x:11,y:10,z:0),player:predicted))
    }
}
