import XCTest
@testable import UOCore
final class LightAssetsTests:XCTestCase {
    func testSignedSamplesAndRectangularIndex() throws {
        let index = Data([0,0,0,0,6,0,0,0,3,0,2,0])
        let assets = try LightAssets(index:index,data:Data([0,31,255,224,16,239]))
        let mask = try XCTUnwrap(assets.mask(0))
        XCTAssertEqual(mask.width,3); XCTAssertEqual(mask.height,2)
        XCTAssertEqual(mask.intensity,[0,248,0,248,128,128])
        XCTAssertNil(try assets.mask(-1)); XCTAssertNil(try assets.mask(1))
        XCTAssertNil(try LightAssets(index:Data(repeating:255,count:12),data:Data()).mask(0))
    }
    func testMalformedLightRecords() throws {
        XCTAssertThrowsError(try LightAssets(index:Data([0]),data:Data()))
        let valid = Data([0,0,0,0,6,0,0,0,3,0,2,0])
        XCTAssertThrowsError(try LightAssets(index:valid,data:Data([1])).mask(0))
        var bad = valid; bad[8] = 0
        XCTAssertThrowsError(try LightAssets(index:bad,data:Data(repeating:0,count:6)).mask(0))
        bad = valid; bad[10] = 3
        XCTAssertThrowsError(try LightAssets(index:bad,data:Data(repeating:0,count:6)).mask(0))
    }
}
