import XCTest
@testable import UOCore

final class ConnectedCeilingTests: XCTestCase {
    func testSeparateRoofsAndCornerContactsStayVisible() {
        typealias C = WorldVisibility.Cell
        let heights = [C(x:0,y:0):20, C(x:1,y:0):25, C(x:1,y:1):30,
                       C(x:2,y:2):30, C(x:4,y:0):20, C(x:0,y:1):80]
        let cells = WorldVisibility.connected(heights, seed: C(x:0,y:0))
        XCTAssertEqual(cells, [C(x:0,y:0),C(x:1,y:0),C(x:1,y:1)])
        let visibility = WorldVisibility(ceiling: 14, ceilingCells: cells)
        XCTAssertTrue(visibility.hides(z:25,x:1,y:0))
        XCTAssertFalse(visibility.hides(z:25,x:4,y:0))
        XCTAssertFalse(visibility.hides(z:0,x:1,y:0))
        XCTAssertFalse(visibility.hidesTerrain(z:25,x:1,y:0))
    }
    func testInspectPacket() {
        XCTAssertEqual(InteractionPackets.inspect(serial:0x12345678), Data([9,0x12,0x34,0x56,0x78]))
    }
}
