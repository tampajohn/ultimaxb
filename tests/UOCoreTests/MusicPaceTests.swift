import XCTest
@testable import UOCore
final class MusicPaceTests:XCTestCase {
    func testExhaustionRemovesRunBitPreservingAllFacings() {
        for direction in UInt8(0)...7 {
            XCTAssertEqual(MovementPace.direction(direction|0x80,stamina:0),direction)
            XCTAssertEqual(MovementPace.direction(direction|0x80,stamina:1),direction)
            XCTAssertEqual(MovementPace.direction(direction|0x80,stamina:2),direction|0x80)
            XCTAssertEqual(MovementPace.direction(direction,stamina:50),direction)
            XCTAssertEqual(MovementPace.direction(direction|0x80,stamina:nil),direction|0x80)
        }
    }
    func testClassicMusicIndexAndStop() throws {
        XCTAssertEqual(MusicCatalog.tracks.count,57)
        XCTAssertEqual(MusicCatalog.track(16)?.name,"minoc")
        XCTAssertEqual(MusicCatalog.track(16)?.loops,true)
        XCTAssertEqual(MusicCatalog.track(42)?.name,"death")
        XCTAssertEqual(MusicCatalog.track(42)?.loops,false)
        XCTAssertEqual(try MusicCatalog.decode(Data([0x6D,255,255])),65535)
        XCTAssertNil(MusicCatalog.track(65535))
        XCTAssertThrowsError(try MusicCatalog.decode(Data([0x6D,1])))
    }
}
