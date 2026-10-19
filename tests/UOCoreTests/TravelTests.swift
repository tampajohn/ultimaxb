import XCTest
@testable import UOCore
final class TravelTests:XCTestCase {
    func testWeightedPathPrefersRoadWithoutIgnoringCollision() throws {
        let start=WalkPoint(x:0,y:0,z:0)
        let route=WalkPath.find(from:start,x:10,y:0,travelCost:{ $0.y==2 ? 1 : 5 }) { p,d in
            let delta=WalkPath.directions[Int(d)],x=p.x+delta.0,y=p.y+delta.1
            guard (0...10).contains(x),(0...3).contains(y),!(x==5 && y==2) else { return nil }
            return WalkPoint(x:x,y:y,z:0)
        }
        XCTAssertNotNil(route); XCTAssertTrue(route!.contains { $0.y==2 })
        XCTAssertFalse(route!.contains(WalkPoint(x:5,y:2,z:0)))
        XCTAssertEqual(route!.last,WalkPoint(x:10,y:0,z:0))
    }
    func testCompleteSearchDetoursAwayFromDestinationToBridge() {
        let start=WalkPoint(x:0,y:0,z:0)
        let route=WalkPath.find(from:start,x:10,y:0,limit:4096,heuristicWeight:3) { p,d in
            let delta=WalkPath.directions[Int(d)],x=p.x+delta.0,y=p.y+delta.1
            guard (0...10).contains(x),(0...30).contains(y),x != 5 || y == 25 else { return nil }
            return WalkPoint(x:x,y:y,z:0)
        }
        XCTAssertEqual(route?.last,WalkPoint(x:10,y:0,z:0))
        XCTAssertTrue(route?.contains(WalkPoint(x:5,y:25,z:0)) == true)
    }
    func testCrowdedCorridorRemainsTraversableAndDoesNotIgnoreWalls() {
        let start=WalkPoint(x:0,y:0,z:0),goal=WalkPoint(x:12,y:0,z:0)
        let enemies=[WorldMobile(serial:2,body:400,x:6,y:0,z:0,notoriety:5)]
        let route=TravelSafety.route(from:start,to:goal,enemies:enemies,cost:{_ in 1}) { p,d in
            let delta=WalkPath.directions[Int(d)],x=p.x+delta.0,y=p.y+delta.1
            return (0...12).contains(x) && y == 0 ? WalkPoint(x:x,y:y,z:0) : nil
        }
        XCTAssertEqual(route?.count,12); XCTAssertEqual(route?.last,goal)
        let blocked=TravelSafety.route(from:start,to:goal,enemies:enemies,cost:{_ in 1}) { p,d in
            let delta=WalkPath.directions[Int(d)],x=p.x+delta.0,y=p.y+delta.1
            return (0...12).contains(x) && y == 0 && x != 6 ? WalkPoint(x:x,y:y,z:0) : nil
        }
        XCTAssertNil(blocked)
    }
    func testThreatPenaltyAndDestinationsValidate() {
        let enemy=WorldMobile(serial:2,body:400,x:5,y:5,z:0,notoriety:5)
        XCTAssertGreaterThan(TravelSafety.penalty(.init(x:0,y:0,z:0),enemies:[enemy]),0)
        XCTAssertTrue(TravelDestination.cities.allSatisfy { $0.valid(width:6144,height:4096) })
        XCTAssertFalse(TravelDestination(name:"",x:0,y:0).valid(width:6144,height:4096))
        XCTAssertFalse(TravelDestination(name:"Bad",x:6144,y:0).valid(width:6144,height:4096))
    }
}
