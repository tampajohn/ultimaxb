import XCTest
@testable import UOCore
final class SpawnMusicTests:XCTestCase {
    func testGracePeriodAndOneFallbackPerConnection() {
        var music=SpawnMusic()
        XCTAssertNil(music.next(regionTrack:16,time:10))
        XCTAssertNil(music.next(regionTrack:16,time:10.9))
        XCTAssertEqual(music.next(regionTrack:16,time:11),16)
        XCTAssertNil(music.next(regionTrack:9,time:20))
        music.reset()
        XCTAssertNil(music.next(regionTrack:9,time:30))
        XCTAssertEqual(music.next(regionTrack:9,time:31),9)
    }
    func testServerTrackOrSilencePreventsFallbackEvenBeforePlayerEntry() {
        var music=SpawnMusic()
        music.serverMusicReceived()
        XCTAssertNil(music.next(regionTrack:16,time:10))
        XCTAssertNil(music.next(regionTrack:16,time:20))
        music.reset()
        _=music.next(regionTrack:16,time:30)
        music.serverMusicReceived()
        XCTAssertNil(music.next(regionTrack:16,time:31))
    }
    func testMissingRegionDoesNotInventMusicOrRetryOnMovement() {
        var music=SpawnMusic()
        _=music.next(regionTrack:nil,time:0)
        XCTAssertNil(music.next(regionTrack:nil,time:1))
        XCTAssertNil(music.next(regionTrack:16,time:2))
    }
}
