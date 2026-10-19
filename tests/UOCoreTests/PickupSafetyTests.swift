import XCTest
@testable import UOCore
final class PickupSafetyTests:XCTestCase {
    let start=WalkPoint(x:10,y:10,z:0)
    func enemy(_ x:Int,_ y:Int)->WorldMobile { WorldMobile(serial:2,body:400,x:x,y:y,z:0) }
    func testShortDetourAllowedWithDistantEnemy() {
        XCTAssertTrue(TravelSafety.pickupIsSafe(from:start,target:WalkPoint(x:12,y:10,z:0),
            path:[WalkPoint(x:11,y:10,z:0)],enemies:[enemy(20,10)]))
    }
    func testCloserEnemyAndClosingGapRejectDetours() {
        XCTAssertFalse(TravelSafety.pickupIsSafe(from:start,target:WalkPoint(x:14,y:10,z:0),path:[],enemies:[enemy(13,10)]))
        let path=[WalkPoint(x:11,y:10,z:0),WalkPoint(x:12,y:10,z:0)]
        XCTAssertFalse(TravelSafety.pickupIsSafe(from:start,target:WalkPoint(x:13,y:10,z:0),path:path,enemies:[enemy(19,10)]))
        XCTAssertFalse(TravelSafety.pickupIsSafe(from:start,target:start,path:[],enemies:[enemy(14,10)]))
    }
    func testWindingDetourTooLongEvenWithoutEnemies() {
        let path=(1...7).map { WalkPoint(x:10+$0,y:10,z:0) }
        XCTAssertFalse(TravelSafety.pickupIsSafe(from:start,target:WalkPoint(x:12,y:10,z:0),path:path,enemies:[]))
    }
}
