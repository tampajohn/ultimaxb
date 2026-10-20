import XCTest
@testable import UOCore

final class HerdingDestinationTests:XCTestCase {
    func testClickChoosesReachableBridgeHeightInsteadOfUnderlyingGround() {
        let start=WalkPoint(x:10,y:10,z:0)
        let slope=WalkPoint(x:11,y:10,z:5),deck=WalkPoint(x:12,y:10,z:10)
        let graph:[WalkPoint:WalkPoint]=[start:slope,slope:deck]
        let resolved=HerdingDestination.resolve(from:start,x:12,y:10) { point,direction in
            direction==2 ? graph[point]:nil
        }
        XCTAssertEqual(resolved,deck)
    }
    func testBlockedOrBudgetExceededClickDoesNotInventHeight() {
        let start=WalkPoint(x:10,y:10,z:0)
        XCTAssertNil(HerdingDestination.resolve(from:start,x:11,y:10) {_,_ in nil})
        XCTAssertNil(HerdingDestination.resolve(from:start,x:11,y:10,limit:0) {_,_ in .init(x:11,y:10,z:0)})
        XCTAssertNil(HerdingDestination.resolve(from:start,x:-1,y:10) {_,_ in XCTFail("Invalid map click cannot search");return nil})
    }
    func testExistingPositionKeepsItsActualHeight() {
        let point=WalkPoint(x:10,y:10,z:-12)
        XCTAssertEqual(HerdingDestination.resolve(from:point,x:10,y:10) {_,_ in XCTFail("Already at destination");return nil},point)
    }
}
