import XCTest
@testable import UOCore

final class WorldEntryDeadlineTests:XCTestCase {
    @MainActor func testUnfinishedWorldEntryFailsOnce() async throws {
        let connection=GameConnection(worldEntryTimeout:.milliseconds(10))
        var failures=0
        connection.onEvent={ if case .failed = $0 { failures += 1 } }
        connection.waitForWorldEntry()
        for _ in 0..<100 {
            if failures>0 { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertEqual(failures,1)
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertEqual(failures,1)
    }
    @MainActor func testConfirmationAndDisconnectCancelPendingDeadline() async throws {
        for disconnect in [false,true] {
            let connection=GameConnection(worldEntryTimeout:.milliseconds(10))
            var failures=0
            connection.onEvent={ if case .failed = $0 { failures += 1 } }
            connection.waitForWorldEntry()
            if disconnect { connection.disconnect(notify:false) }
            else { connection.finishWorldEntryWait() }
            try await Task.sleep(for:.milliseconds(40))
            XCTAssertEqual(failures,0)
        }
    }
    @MainActor func testOldDeadlineCannotFailReplacementWait() async throws {
        let connection=GameConnection(worldEntryTimeout:.milliseconds(40))
        var failures=0
        connection.onEvent={ if case .failed = $0 { failures += 1 } }
        connection.waitForWorldEntry()
        connection.disconnect(notify:false)
        connection.waitForWorldEntry()
        connection.finishWorldEntryWait()
        try await Task.sleep(for:.milliseconds(70))
        XCTAssertEqual(failures,0)
    }
}
