import XCTest
@testable import UOCore

final class ClassicFontsTests: XCTestCase {
    func fixture() -> Data {
        var data = Data([0])
        for code in 32...255 {
            if code == 65 { data.append(contentsOf:[2,1,0,0,0,0,0x7C]) }
            else { data.append(contentsOf:[0,0,0]) }
        }
        return data
    }
    func testGlyphPixelsTransparencyAndFontBounds() throws {
        let fonts = try ClassicFonts(data:fixture())
        XCTAssertEqual(fonts.count,1)
        let glyph = try XCTUnwrap(fonts.glyph("A",font:0))
        XCTAssertEqual(glyph.sprite.width,2)
        XCTAssertEqual(glyph.sprite.rgba,[0,0,0,0,255,0,0,255])
        XCTAssertEqual(glyph.offsetY,0)
        XCTAssertEqual(try fonts.glyph("a",font:0)?.offsetY,2)
        XCTAssertNil(try fonts.glyph("A",font:1))
        XCTAssertNil(try fonts.glyph("界",font:0))
        XCTAssertNil(try fonts.glyph("\n",font:0))
    }
    func testTruncationNeverExposesPartialFont() throws {
        XCTAssertThrowsError(try ClassicFonts(data:Data()))
        XCTAssertThrowsError(try ClassicFonts(data:fixture().dropLast()))
        XCTAssertEqual(try ClassicFonts(data:fixture()+fixture().prefix(20)).count,1)
        XCTAssertEqual(try ClassicFonts(data:fixture()+fixture()).count,2)
    }
}
