import XCTest
@testable import UOCore

final class WalkDestinationTests: XCTestCase {
    let player = WalkPoint(x:8,y:10,z:0)
    let roof = WalkPoint(x:10,y:10,z:20)
    func testRoofMapsToFloorAtSameWorldCoordinates() {
        let result = WalkDestination.beneathRoof(roof,footprint:[],player:player) { x,y in WalkPoint(x:x,y:y,z:0) }
        XCTAssertEqual(result,WalkPoint(x:10,y:10,z:0))
    }
    func testEaveOnWallUsesNearbyCoveredFloor() {
        let interior = WalkPoint(x:11,y:10,z:24)
        let result = WalkDestination.beneathRoof(roof,footprint:[interior],player:player) { x,y in
            x == 10 ? nil : WalkPoint(x:x,y:y,z:0)
        }
        XCTAssertEqual(result,WalkPoint(x:11,y:10,z:0))
    }
    func testDoesNotSelectRoofOrUncoveredTerrainOrDistantBuilding() {
        XCTAssertNil(WalkDestination.beneathRoof(roof,footprint:[],player:player) { x,y in WalkPoint(x:x,y:y,z:20) })
        XCTAssertNil(WalkDestination.beneathRoof(roof,footprint:[WalkPoint(x:20,y:10,z:20)],player:player) { x,y in
            x == 10 ? nil : WalkPoint(x:x,y:y,z:0)
        })
        XCTAssertNil(WalkDestination.beneathRoof(roof,footprint:[WalkPoint(x:12,y:10,z:20)],player:player) { x,y in
            x == 10 ? nil : WalkPoint(x:x,y:y,z:0)
        }, "Do not jump a gap into another building")
        XCTAssertNil(WalkDestination.beneathRoof(roof,footprint:[],player:player) { _,_ in nil })
    }
}
