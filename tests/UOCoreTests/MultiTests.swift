import XCTest
@testable import UOCore
final class MultiTests: XCTestCase {
    func testInvisibleRootIsDrawnButServerOwnedHatchIsNot() throws {
        let index = Data([0,0,0,0,36,0,0,0,0,0,0,0])
        let data = Data([
            0xDD,0x3E,0,0,0,0,0,0,0,0,0,0, // root mast
            0xAE,0x3E,0,0,252,255,0,0,0,0,0,0, // separate hatch
            0xDE,0x3E,2,0,0,0,0,0,1,0,0,0 // visible sail
        ])
        let tiles = try MultiAssets(index:index,data:data).tiles(id:0,x:100,y:200,z:0)
        XCTAssertEqual(tiles.map(\.art),[0x7EDD,0x7EDE])
        XCTAssertEqual(tiles[0].x,100); XCTAssertEqual(tiles[0].y,200)
        XCTAssertEqual(tiles[1].x,102)
    }
    func testSignedOffsetsAndInvisibleComponents() throws {
        let index = Data([0,0,0,0,24,0,0,0,0,0,0,0])
        let data = Data([1,0,255,255,2,0,251,255,1,0,0,0, 2,0,0,0,0,0,0,0,0,0,0,0])
        let tiles = try MultiAssets(index:index,data:data).tiles(id:0,x:100,y:200,z:10)
        XCTAssertEqual(tiles.count,1)
        XCTAssertEqual(tiles[0].x,99); XCTAssertEqual(tiles[0].y,202)
        XCTAssertEqual(tiles[0].z,5); XCTAssertEqual(tiles[0].art,0x4001)
        XCTAssertThrowsError(try MultiAssets(index:index,data:Data()).tiles(id:0,x:0,y:0,z:0))
    }
}
