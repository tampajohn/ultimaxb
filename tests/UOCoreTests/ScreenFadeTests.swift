import XCTest
@testable import UOCore

final class ScreenFadeTests: XCTestCase {
    func testSimpleFadeTimingAndRelease() {
        for style in [0,1,2,4] {
            let fade = ScreenFade(style:style,at:10)
            XCTAssertEqual(fade.sample(at:10)?.opacity,0)
            XCTAssertEqual(fade.sample(at:10+fade.duration/2)!.opacity,0.5,accuracy:0.0001)
            XCTAssertEqual(fade.sample(at:10.01)?.white,style == 0 || style == 4 ? 0 : 1)
            XCTAssertNil(fade.sample(at:10+fade.duration))
            XCTAssertNil(fade.sample(at:1000))
        }
        XCTAssertEqual(ScreenFade(style:2,at:0).duration,0.375,accuracy:0.0001)
        XCTAssertEqual(ScreenFade(style:4,at:0).duration,0.2,accuracy:0.0001)
    }
    func testWhiteHoldDimBlackHoldAndRelease() {
        let fade = ScreenFade(style:3,at:0)
        XCTAssertEqual(fade.sample(at:0.75),.init(white:1,opacity:0.5))
        XCTAssertEqual(fade.sample(at:2),.init(white:1,opacity:1))
        XCTAssertEqual(fade.sample(at:3.25),.init(white:0.5,opacity:1))
        XCTAssertEqual(fade.sample(at:4.25),.init(white:0,opacity:1))
        XCTAssertNil(fade.sample(at:4.5))
    }
    func testInvalidClockAndClampedServerStyle() {
        XCTAssertNil(ScreenFade(style:0,at:.nan).sample(at:0))
        XCTAssertNil(ScreenFade(style:0,at:0).sample(at:.infinity))
        XCTAssertNil(ScreenFade(style:0,at:1).sample(at:0))
        XCTAssertEqual(ScreenFade(style:65535,at:0).style,4)
        XCTAssertEqual(ScreenFade(style:-1,at:0).style,0)
    }
}
