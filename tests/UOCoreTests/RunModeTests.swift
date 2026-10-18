import XCTest
@testable import UOCore
final class RunModeTests: XCTestCase {
    func testChatClearsLatchUntilAnotherCapsCycle() {
        var mode = RunMode()
        mode.update(capsLock:true,chatting:false)
        XCTAssertTrue(mode.running(shift:false))
        mode.update(capsLock:true,chatting:true)
        XCTAssertFalse(mode.alwaysRun)
        mode.update(capsLock:true,chatting:false)
        XCTAssertFalse(mode.running(shift:false))
        XCTAssertTrue(mode.running(shift:true))
        mode.update(capsLock:false,chatting:false)
        mode.update(capsLock:true,chatting:false)
        XCTAssertTrue(mode.alwaysRun)
        mode.update(capsLock:false,chatting:true)
        mode.update(capsLock:true,chatting:true)
        mode.update(capsLock:true,chatting:false)
        XCTAssertFalse(mode.alwaysRun)
    }
}
