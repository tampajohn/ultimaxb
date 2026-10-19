import XCTest
@testable import UOCore
final class ReverseWalkSearchTests:XCTestCase {
    func testForwardRouteReconstructedAcrossOneWayDrop() throws {
        let start=WalkPoint(x:0,y:0,z:20),low=WalkPoint(x:1,y:0,z:0),goal=WalkPoint(x:2,y:0,z:0)
        let incoming=[low:[start],goal:[low]]
        let result=ReverseWalkSearch.find(from:start,goals:[goal],limit:10) { incoming[$0] ?? [] }
        XCTAssertEqual(result.route,[low,goal])
        let uphill=ReverseWalkSearch.find(from:goal,goals:[start],limit:10) { incoming[$0] ?? [] }
        XCTAssertNil(uphill.route)
        XCTAssertEqual(uphill.statistics.outcome,.exhausted)
    }
    func testBudgetIsNotDisconnectionAndMultipleGoalLevelsAreRetained() {
        let start=WalkPoint(x:0,y:0,z:0),bridge=WalkPoint(x:1,y:0,z:5),floor=WalkPoint(x:1,y:0,z:0)
        let result=ReverseWalkSearch.find(from:start,goals:[floor,bridge],limit:10) { $0==bridge ? [start] : [] }
        XCTAssertEqual(result.route,[bridge])
        let limited=ReverseWalkSearch.find(from:start,goals:[bridge],limit:0) { _ in [start] }
        XCTAssertEqual(limited.statistics.outcome,.budgetExceeded)
    }
    func testCyclesTerminateAndCancellationPropagates() {
        let a=WalkPoint(x:0,y:0,z:0),b=WalkPoint(x:1,y:0,z:0),start=WalkPoint(x:9,y:9,z:0)
        let result=ReverseWalkSearch.find(from:start,goals:[a],limit:10) { $0==a ? [b] : [a] }
        XCTAssertEqual(result.statistics.outcome,.exhausted)
        XCTAssertEqual(result.statistics.expanded,2)
        XCTAssertThrowsError(try ReverseWalkSearch.find(from:start,goals:[a],limit:10) { _ in throw CancellationError() })
    }
}
