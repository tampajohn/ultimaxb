import XCTest
@testable import UOCore
final class NavigationTests:XCTestCase {
    func testShortestRouteAroundWallAndBoundedFailure() {
        let start = WalkPoint(x:0,y:0,z:0)
        func step(_ p:WalkPoint,_ d:UInt8)->WalkPoint? {
            let delta = WalkPath.directions[Int(d)]
            let n = WalkPoint(x:p.x+delta.0,y:p.y+delta.1,z:0)
            guard (0...5).contains(n.x), (0...5).contains(n.y), !(n.x==2 && n.y<4) else { return nil }
            return n
        }
        let route = WalkPath.find(from:start,x:4,y:0,step:step)
        XCTAssertEqual(route?.last,WalkPoint(x:4,y:0,z:0))
        XCTAssertTrue(route!.contains { $0.y == 4 })
        XCTAssertNil(WalkPath.find(from:start,x:4,y:0,limit:1,step:step))
        XCTAssertEqual(WalkPath.find(from:start,x:0,y:0,step:step),[])
        let near = WalkPath.find(from:start,x:1,y:0,adjacent:true,step:step)
        XCTAssertEqual(near,[])
        XCTAssertNil(WalkPath.find(from:start,x:1,y:0,adjacent:true,goalZ:50,step:step))
    }
    func testToolApproachReachesCliffWithoutClimbingTargetZ() throws {
        let target = TargetSelection(x:5,y:0,z:60,graphic:0)
        XCTAssertTrue(ToolReach.needsApproach(playerX:0,playerY:0,target:target))
        let route = try XCTUnwrap(WalkPath.find(from:WalkPoint(x:0,y:0,z:0),x:5,y:0,adjacent:true) { point,direction in
            let delta = WalkPath.directions[Int(direction)]
            let next = WalkPoint(x:point.x+delta.0,y:point.y+delta.1,z:0)
            return (0..<5).contains(next.x) && (-2...2).contains(next.y) ? next : nil
        })
        let last = try XCTUnwrap(route.last)
        XCTAssertFalse(ToolReach.needsApproach(playerX:last.x,playerY:last.y,target:target))
        XCTAssertEqual(last.z,0)
        XCTAssertFalse(route.contains { $0.x == target.x && $0.y == target.y })
    }
    func testApproachStopsBesideBlockedTarget() throws {
        let target = WalkPoint(x:5,y:0,z:0)
        let start = WalkPoint(x:0,y:0,z:0)
        let route = try XCTUnwrap(WalkPath.find(from:start,x:target.x,y:target.y,adjacent:true,goalZ:0) { p,d in
            let delta = WalkPath.directions[Int(d)]
            let next = WalkPoint(x:p.x+delta.0,y:p.y+delta.1,z:0)
            guard next != target, (0...5).contains(next.x), (-2...2).contains(next.y) else { return nil }
            return next
        })
        XCTAssertEqual(route.count,4)
        let end = try XCTUnwrap(route.last)
        XCTAssertEqual(max(abs(end.x-target.x),abs(end.y-target.y)),1)
        XCTAssertFalse(route.contains(target))
    }
    func testOpenGroundPrefersDirectLineWithoutZigzags() throws {
        let start = WalkPoint(x:10,y:10,z:0)
        for (dx,dy) in [(8,0),(-8,0),(0,8),(0,-8),(8,8),(-8,8),(8,-8),(-8,-8)] {
            let route = try XCTUnwrap(WalkPath.find(from:start,x:start.x+dx,y:start.y+dy) { p,d in
                let delta = WalkPath.directions[Int(d)]
                return WalkPoint(x:p.x+delta.0,y:p.y+delta.1,z:0)
            })
            XCTAssertEqual(route.count,8)
            for (i,p) in route.enumerated() {
                XCTAssertEqual(p.x,start.x+dx.signum()*(i+1))
                XCTAssertEqual(p.y,start.y+dy.signum()*(i+1))
            }
        }
    }
    func testLongJourneyContinuesAcrossFreshLocalSnapshots() throws {
        var current = WalkPoint(x:0,y:0,z:0)
        var segments = 0
        while current.x != 100 {
            let center = current
            let route = try XCTUnwrap(WalkPath.find(from:current,x:100,y:0,segmentLength:32) { p,d in
                let delta = WalkPath.directions[Int(d)]
                let next = WalkPoint(x:p.x+delta.0,y:p.y+delta.1,z:0)
                return max(abs(next.x-center.x),abs(next.y-center.y)) <= 48 ? next : nil
            })
            XCTAssertFalse(route.isEmpty); XCTAssertLessThanOrEqual(route.count,32)
            current = try XCTUnwrap(route.last); segments += 1
            XCTAssertLessThan(segments,5)
        }
        XCTAssertEqual(segments,4)
        XCTAssertEqual(current.y,0)
    }
    func testCollisionSurfacesAndHeadroom() {
        typealias C = NavigationMap.Cell
        typealias S = NavigationMap.Surface
        XCTAssertEqual(C(landZ:0,lowZ:0,landBlocked:false,surfaces:[]).standingZ(from:0),0)
        XCTAssertNil(C(landZ:0,lowZ:0,landBlocked:true,surfaces:[]).standingZ(from:0))
        XCTAssertNil(C(landZ:0,lowZ:0,landBlocked:false,surfaces:[S(z:0,height:20,flags:0x40)]).standingZ(from:0))
        XCTAssertEqual(C(landZ:0,lowZ:0,landBlocked:false,surfaces:[S(z:0,height:8,flags:0x200)]).standingZ(from:0),8)
        XCTAssertNil(C(landZ:0,lowZ:0,landBlocked:false,surfaces:[S(z:10,height:5,flags:0x40)]).standingZ(from:0))
        XCTAssertEqual(C(landZ:12,lowZ:4,landBlocked:false,surfaces:[]).standingZ(from:0),12)
        XCTAssertEqual(C(landZ:0,lowZ:0,landBlocked:true,surfaces:[S(z:0,height:10,flags:0x600)]).standingZ(from:0),5)
        XCTAssertEqual(C(landZ:0,lowZ:0,landBlocked:true,surfaces:[S(z:0,height:0,flags:0x200)]).standingZ(from:0),0)
        XCTAssertNil(C(landZ:40,lowZ:40,landBlocked:false,surfaces:[]).standingZ(from:0))
    }
}
