import XCTest
@testable import UOCore
final class NavigationTests:XCTestCase {
    func testSearchBudgetCountsExpandedTilesNotStaleQueueEntries() {
        let start=WalkPoint(x:0,y:0,z:0),a=WalkPoint(x:9,y:0,z:0),b=WalkPoint(x:1,y:0,z:0)
        let c=WalkPoint(x:-10,y:0,z:0),goal=WalkPoint(x:10,y:0,z:0)
        var stats:WalkPath.SearchStatistics?
        let path=WalkPath.find(from:start,x:goal.x,y:goal.y,limit:5,heuristicWeight:3,
            travelCost:{ $0==a ? 5 : ($0==goal ? 100 : 1) },report:{stats=$0}) { p,d in
                if p==start { return d==0 ? a : (d==1 ? b : nil) }
                if (p==a || p==b) && d==0 { return c }
                if p==c && d==0 { return goal }
                return nil
            }
        XCTAssertEqual(path,[b,c,goal])
        XCTAssertEqual(stats?.outcome,.found)
        XCTAssertEqual(stats?.expanded,4)
        XCTAssertEqual(stats?.popped,6)
    }
    func testSearchDistinguishesBudgetFromDisconnectedGoal() {
        let start=WalkPoint(x:0,y:0,z:0)
        var stats:WalkPath.SearchStatistics?
        XCTAssertNil(WalkPath.find(from:start,x:10,y:0,limit:0,report:{stats=$0},step:{_,_ in nil}))
        XCTAssertEqual(stats?.outcome,.budgetExceeded)
        XCTAssertNil(WalkPath.find(from:start,x:10,y:0,limit:10,report:{stats=$0},step:{_,_ in nil}))
        XCTAssertEqual(stats?.outcome,.exhausted)
    }

    func testPickupRouteStopsTwoTilesAway() {
        let start=WalkPoint(x:0,y:0,z:0)
        let route=WalkPath.find(from:start,x:5,y:0,goalRadius:2) { point,direction in
            let delta=WalkPath.directions[Int(direction)]
            return WalkPoint(x:point.x+delta.0,y:point.y+delta.1,z:0)
        }
        XCTAssertEqual(route?.count,3)
        XCTAssertEqual(route?.last,WalkPoint(x:3,y:0,z:0))
        XCTAssertEqual(WalkPath.find(from:start,x:2,y:0,goalRadius:2,step:{ _,_ in nil }),[])
    }

    func testGhostPassabilityKeepsWallsWaterAndFloorSupport() {
        typealias S = NavigationMap.Surface
        typealias C = NavigationMap.Cell
        let door = S(z:0,height:20,flags:0x20000040,ghostPassable:true)
        let wall = S(z:0,height:20,flags:0x40)
        let doorway = C(landZ:0,lowZ:0,landBlocked:false,surfaces:[door])
        XCTAssertNil(doorway.standingZ(from:0))
        XCTAssertEqual(doorway.standingZ(from:0,ghost:true),0)
        XCTAssertNil(C(landZ:0,lowZ:0,landBlocked:false,surfaces:[door,wall]).standingZ(from:0,ghost:true))
        XCTAssertNil(C(landZ:0,lowZ:0,landBlocked:true,surfaces:[door]).standingZ(from:0,ghost:true))
        let platform = S(z:0,height:6,flags:0x200,ghostPassable:true)
        XCTAssertEqual(C(landZ:-20,lowZ:-20,landBlocked:true,surfaces:[platform]).standingZ(from:0,ghost:true),6,
                       "Ghost exceptions must preserve supporting surfaces over blocked terrain")
        XCTAssertNil(doorway.standingZ(from:0), "Living movement must still collide after resurrection")
    }
    func testGhostExceptionsDistinguishWorldItemsFromBuildingComponents() {
        typealias S = NavigationMap.Surface
        XCTAssertTrue(S.passableForGhost(graphic:0x675,flags:0x20000040,dynamic:true,weight:255))
        for id in [0x692,0x6F5,0x6F6,0x846,0x873] {
            XCTAssertTrue(S.passableForGhost(graphic:id,flags:0x40,dynamic:false,weight:255))
        }
        XCTAssertTrue(S.passableForGhost(graphic:0xE3C,flags:0x40,dynamic:true,weight:90))
        XCTAssertFalse(S.passableForGhost(graphic:0xE3C,flags:0x40,dynamic:true,weight:91))
        XCTAssertFalse(S.passableForGhost(graphic:0xE3C,flags:0x40,dynamic:false,weight:1))
        XCTAssertFalse(S.passableForGhost(graphic:0x80,flags:0x40,dynamic:true,weight:255))
        XCTAssertTrue(WorldMobile(serial:1,body:402,x:0,y:0,z:0).isGhost)
        XCTAssertTrue(WorldMobile(serial:1,body:403,x:0,y:0,z:0).isGhost)
        XCTAssertFalse(WorldMobile(serial:1,body:400,x:0,y:0,z:0).isGhost)
    }
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
