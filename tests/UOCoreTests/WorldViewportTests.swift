import XCTest
@testable import UOCore
final class WorldViewportTests:XCTestCase {
    func testHorizontalFieldOfViewChangesWithoutSquashingHeight() {
        let normal=WorldViewport(availableWidth:960,availableHeight:720)
        let wide=WorldViewport(availableWidth:1440,availableHeight:720)
        let narrow=WorldViewport(availableWidth:640,availableHeight:720)
        XCTAssertEqual([normal.width,wide.width,narrow.width],[960,1440,640])
        XCTAssertEqual([normal.height,wide.height,narrow.height],[720,720,720])
    }
    func testExtremeAspectKeepsAspectWithinRasterBudget() {
        let wide=WorldViewport(availableWidth:4096,availableHeight:720)
        XCTAssertEqual(wide.width,2048); XCTAssertEqual(wide.height,360)
        let minimized=WorldViewport(availableWidth:0,availableHeight:0)
        XCTAssertTrue(minimized.width>0 && minimized.height>0)
    }
}
