import XCTest
@testable import UOCore
final class HarvestSitePlannerTests:XCTestCase {
    let start=WalkPoint(x:10,y:10,z:0)
    func zone()throws->HarvestWorkflow.Zone { try .init(x1:10,y1:10,x2:14,y2:14) }
    func tile(_ x:Int,_ y:Int,art:Int=0xDC,z:Int=20)->WorldTile { .init(x:x,y:y,z:z,art:art,hue:0) }
    func step(_ p:WalkPoint,_ d:UInt8)->WalkPoint? {
        let delta=WalkPath.directions[Int(d)]
        return .init(x:p.x+delta.0,y:p.y+delta.1,z:0)
    }
    func testEraRulesDistinguishLandFromStaticAndRejectGaps() {
        XCTAssertTrue(HarvestSitePlanner.accepts(kind:.mining,graphic:0xDC,isStatic:false))
        XCTAssertFalse(HarvestSitePlanner.accepts(kind:.mining,graphic:0xDC,isStatic:true))
        XCTAssertTrue(HarvestSitePlanner.accepts(kind:.mining,graphic:0x16E4,isStatic:true))
        XCTAssertFalse(HarvestSitePlanner.accepts(kind:.mining,graphic:0x550,isStatic:true))
        XCTAssertTrue(HarvestSitePlanner.accepts(kind:.lumberjacking,graphic:0xCCA,isStatic:true))
        XCTAssertFalse(HarvestSitePlanner.accepts(kind:.lumberjacking,graphic:0xCCA,isStatic:false))
        XCTAssertFalse(HarvestSitePlanner.accepts(kind:.lumberjacking,graphic:0xCE7,isStatic:true))
    }
    func testTargetRetainsZAndUsesLandReplyWhileStandingOnReachableFloor()throws {
        let plan=HarvestSitePlanner.discover(zone:try zone(),kind:.mining,start:start,tiles:[tile(11,10)]) { _,_ in nil }
        XCTAssertEqual(plan.sites.count,1)
        XCTAssertEqual(plan.sites[0].standing,start)
        XCTAssertEqual(plan.sites[0].target,.init(x:11,y:10,z:20,graphic:0))
    }
    func testWallAndZoneEdgesExcludeUnreachableTargets()throws {
        let plan=HarvestSitePlanner.discover(zone:try zone(),kind:.mining,start:start,tiles:[tile(14,10),tile(9,10),tile(11,10)]) { p,d in
            let next=self.step(p,d)!
            return next.x>11 ? nil : next
        }
        XCTAssertEqual(plan.sites.map(\.target.x),[11])
        XCTAssertTrue(plan.sites.allSatisfy { $0.standing.x<=11 })
    }
    func testDuplicateAndDynamicObjectsDoNotAddWork()throws {
        let tree=tile(11,10,art:0x4CCA)
        var dynamic=tile(12,10,art:0x4CCB); dynamic.isDynamic=true
        let plan=HarvestSitePlanner.discover(zone:try zone(),kind:.lumberjacking,start:start,tiles:[tree,tree,dynamic],step:step)
        XCTAssertEqual(plan.sites.count,1)
        XCTAssertEqual(plan.sites[0].target.graphic,0xCCA)
    }
    func testBoundedSearchReportsTruncationAndRejectsJumpSteps()throws {
        let plan=HarvestSitePlanner.discover(zone:try zone(),kind:.mining,start:start,tiles:[tile(14,14)],limit:1,step:step)
        XCTAssertTrue(plan.searchTruncated); XCTAssertEqual(plan.reachablePoints,1); XCTAssertTrue(plan.sites.isEmpty)
        let invalid=HarvestSitePlanner.discover(zone:try zone(),kind:.mining,start:start,tiles:[tile(14,14)]) { _,_ in .init(x:14,y:14,z:0) }
        XCTAssertEqual(invalid.reachablePoints,1); XCTAssertTrue(invalid.sites.isEmpty)
    }
}
