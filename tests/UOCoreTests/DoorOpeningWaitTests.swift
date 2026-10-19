import XCTest
@testable import UOCore

final class DoorOpeningWaitTests: XCTestCase {
    func door(serial: UInt32 = 1, graphic: Int = 0x675, x: Int = 10, hue: Int = 0) -> GroundItem {
        GroundItem(serial: serial, graphic: graphic, amount: 1, x: x, y: 10, z: 0, direction: 0, hue: hue, flags: 0)
    }
    func testOnlySameDoorGeometryChangeCanResume() {
        let wait = DoorOpeningWait(door: door(), at: 10)
        XCTAssertEqual(wait.result(door: door(), at: 11), .waiting)
        XCTAssertEqual(wait.result(door: nil, at: 11), .waiting)
        XCTAssertEqual(wait.result(door: door(serial: 2, graphic: 0x676), at: 11), .waiting)
        XCTAssertEqual(wait.result(door: door(hue: 20), at: 11), .waiting)
        XCTAssertEqual(wait.result(door: door(graphic: 0x676), at: 11), .changed)
        XCTAssertEqual(wait.result(door: door(x: 11), at: 11), .changed)
    }
    func testApproachSnapshotDetectsDoorAlreadyChanged() {
        XCTAssertTrue(DoorOpeningWait.geometryChanged(from:door(),to:door(graphic:0x676)))
        XCTAssertTrue(DoorOpeningWait.geometryChanged(from:door(),to:door(x:11)))
        XCTAssertFalse(DoorOpeningWait.geometryChanged(from:door(),to:door(hue:5)))
        XCTAssertFalse(DoorOpeningWait.geometryChanged(from:door(),to:door(serial:2,graphic:0x676)))
    }
    func testLockedMissingOrLateDoorTimesOut() {
        let wait = DoorOpeningWait(door: door(), at: 10)
        XCTAssertEqual(wait.result(door: door(), at: 14), .timedOut)
        XCTAssertEqual(wait.result(door: nil, at: 14), .timedOut)
        XCTAssertEqual(wait.result(door: door(graphic: 0x676), at: 15), .timedOut)
    }
    func testExplicitThrottleRetriesAreDelayedAndBounded() {
        var wait=DoorOpeningWait(door:door(),at:0)
        wait.throttled(at:0.1)
        XCTAssertEqual(wait.result(door:door(),at:2),.waiting)
        XCTAssertEqual(wait.result(door:door(),at:2.1),.retry)
        wait.didRetry(at:2.1)
        wait.throttled(at:2.2)
        XCTAssertEqual(wait.result(door:door(graphic:0x676),at:3),.changed)
        XCTAssertEqual(wait.result(door:door(),at:4.2),.retry)
        wait.didRetry(at:4.2)
        wait.throttled(at:4.3)
        XCTAssertEqual(wait.result(door:door(),at:6.5),.waiting)
        XCTAssertEqual(wait.result(door:door(),at:8.3),.timedOut)
        XCTAssertEqual(wait.retries,2)
    }
    func testUncorrelatedThrottleDoesNotEnableRetry() {
        var wait=DoorOpeningWait(door:door(),at:0)
        wait.throttled(at:3)
        XCTAssertEqual(wait.result(door:door(),at:4),.timedOut)
    }
    func testOpenedLeavesCannotBeCrossedOrCutDiagonally() {
        let start=WalkPoint(x:10,y:10,z:0),leaf=WalkPoint(x:11,y:10,z:0)
        XCTAssertFalse(TravelSafety.clearsDoorLeaves(from:start,to:leaf,leaves:[leaf]))
        XCTAssertFalse(TravelSafety.clearsDoorLeaves(from:start,to:WalkPoint(x:11,y:11,z:0),leaves:[leaf]))
        XCTAssertTrue(TravelSafety.clearsDoorLeaves(from:start,to:WalkPoint(x:10,y:11,z:0),leaves:[leaf]))
    }
    func testPlanningPastDoorDoesNotRemoveWallsOrBlockedLand() {
        let door = NavigationMap.Surface(z: 0, height: 20, flags: 0x20000040)
        let wall = NavigationMap.Surface(z: 0, height: 20, flags: 0x40)
        let doorway = NavigationMap.Cell(landZ: 0, lowZ: 0, landBlocked: false, surfaces: [door])
        XCTAssertNil(doorway.standingZ(from: 0))
        XCTAssertEqual(doorway.standingZ(from: 0, ignoringDoors: true), 0)
        let obstructed = NavigationMap.Cell(landZ: 0, lowZ: 0, landBlocked: false, surfaces: [door, wall])
        XCTAssertNil(obstructed.standingZ(from: 0, ignoringDoors: true))
        let water = NavigationMap.Cell(landZ: 0, lowZ: 0, landBlocked: true, surfaces: [door])
        XCTAssertNil(water.standingZ(from: 0, ignoringDoors: true))
    }
}
