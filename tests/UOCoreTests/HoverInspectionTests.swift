import XCTest
@testable import UOCore
final class HoverInspectionTests:XCTestCase {
    func testThrottleAndExpiry() {
        var limiter=HoverInspection()
        XCTAssertFalse(limiter.shouldRequest(0,at:0))
        XCTAssertFalse(limiter.shouldRequest(UInt32.max,at:0))
        XCTAssertTrue(limiter.shouldRequest(1,at:0))
        XCTAssertFalse(limiter.shouldRequest(2,at:0.1))
        XCTAssertTrue(limiter.shouldRequest(2,at:0.25))
        XCTAssertFalse(limiter.shouldRequest(1,at:1.9))
        XCTAssertTrue(limiter.shouldRequest(1,at:2))
        limiter=HoverInspection()
        XCTAssertTrue(limiter.shouldRequest(1,at:2.01))
    }
}
