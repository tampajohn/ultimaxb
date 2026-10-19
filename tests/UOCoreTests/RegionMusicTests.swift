import XCTest
@testable import UOCore
final class RegionMusicTests:XCTestCase {
    func testTownOverridesForestAndWeatherlessBuildingsInEitherInputOrder() throws {
        let rows=[
            "1 0 0 128 128 -127 127 0 FOREST 27 0 0 0 0",
            "2 32 32 32 32 -127 127 0 TOWN 16 0 0 0 0",
            "3 40 40 8 8 -127 127 0 SHOP 0 0 0 0 0"
        ]
        for ordered in [rows,Array(rows.reversed())] {
            let map=try RegionMusic(text:"version 64207\n"+ordered.joined(separator:"\n"))
            XCTAssertEqual(map.track(x:40,y:40),16)
            XCTAssertEqual(map.track(x:16,y:16),27)
            XCTAssertNil(map.track(x:200,y:200))
            // Inclusive block assignment extends the town through block 8.
            XCTAssertEqual(map.track(x:71,y:71),16)
            XCTAssertEqual(map.track(x:72,y:72),27)
            XCTAssertNil(map.track(x:-1,y:40))
        }
    }
    func testWeatherOnlyRegionClearsMusicAndUnknownTrackIsNotPlayable() throws {
        let map=try RegionMusic(text:"""
        version 64207
        1 0 0 128 128 -127 127 0 FOREST 27 0 0 0 0
        2 32 32 8 8 -127 127 0 WEATHER 0 1 0 0 0
        3 64 64 8 8 -127 127 0 UNKNOWN 999 0 0 0 0
        """)
        XCTAssertNil(map.track(x:32,y:32))
        XCTAssertNil(map.track(x:64,y:64))
    }
    func testOldFormatAndMalformedInput() throws {
        XCTAssertEqual(try RegionMusic(text:"version 64206\n1 0 0 8 8 -127 127 0 TOWN 16 0 0").track(x:0,y:0),16)
        for text in ["version 1", "version 64207\n1 0", "version 64207\n1 0 0 99999999 8 -127 127 0 X 16 0 0 0 0"] {
            XCTAssertThrowsError(try RegionMusic(text:text))
        }
    }
}
