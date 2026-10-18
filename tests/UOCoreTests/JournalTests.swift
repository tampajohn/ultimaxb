import XCTest
@testable import UOCore
final class JournalTests:XCTestCase {
    func testBoundedHistoryAndReset() {
        var journal = Journal(maximumLines:3,maximumBytes:10)
        for text in ["one","two","three"] { journal.append(text) }
        XCTAssertEqual(journal.lines,["two","three"]); XCTAssertEqual(journal.byteCount,8)
        journal.append("x"); journal.append("y")
        XCTAssertEqual(journal.lines,["three","x","y"])
        journal.clear(); XCTAssertEqual(journal.lines,[]); XCTAssertEqual(journal.byteCount,0)
    }
    func testUnicodeAndOversizedInput() {
        var journal = Journal(maximumBytes:7)
        journal.append("😀😀")
        XCTAssertEqual(journal.lines,["😀"]); XCTAssertEqual(journal.byteCount,4)
        journal.append(""); XCTAssertEqual(journal.lines.count,1)
        var disabled = Journal(maximumLines:0); disabled.append("hidden")
        XCTAssertTrue(disabled.lines.isEmpty)
    }
}
