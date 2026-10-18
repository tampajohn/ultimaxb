import XCTest
@testable import UOCore

final class HelpPacketsTests:XCTestCase {
    func testLegacyHelpRequestHasEmptyTypeAndText() {
        XCTAssertEqual(HelpPackets.request.count,258)
        XCTAssertEqual(HelpPackets.request.first,0x9B)
        XCTAssertTrue(HelpPackets.request.dropFirst().allSatisfy { $0 == 0 })
    }
}
