import Foundation
import XCTest
@testable import UOCore

final class AnimationTests: XCTestCase {
    func record(header: UInt32 = 0xFFFFE002) -> Data {
        var d = Data(repeating: 0, count: 512)
        d[2] = 0; d[3] = 0x7C // palette 1: red
        d[4] = 0xE0; d[5] = 3 // palette 2: green
        func word(_ x: UInt16) { d += Data([UInt8(truncatingIfNeeded: x), UInt8(x >> 8)]) }
        func dword(_ x: UInt32) { word(UInt16(truncatingIfNeeded: x)); word(UInt16(x >> 16)) }
        dword(1); dword(8) // one frame; relative to byte 512
        word(1); word(0); word(2); word(2)
        // Signed x=-1,y=-2 plus anchors (1,2) yields top-left.
        dword(header); d += Data([1, 2]); dword(0x7FFF7FFF)
        return d
    }
    func testSignedRunsPaletteAnchorsAndTransparency() throws {
        let frame = try AnimationDecoder.decode(Bytes(record()), frame: 0)
        XCTAssertEqual(frame.centerX, 1)
        XCTAssertEqual(frame.centerY, 0)
        XCTAssertEqual(frame.sprite.width, 2)
        XCTAssertEqual(frame.sprite.rgba, [255,0,0,255, 0,255,0,255, 0,0,0,0, 0,0,0,0])
        XCTAssertThrowsError(try AnimationDecoder.decode(Bytes(record(header: 0xFFFFE003)), frame: 0))
        for length in 0..<record().count {
            XCTAssertThrowsError(try AnimationDecoder.decode(Bytes(Data(record().prefix(length))), frame: 0))
        }
    }
    func testDirectionMappingCacheAndMissingRecords() throws {
        let raw = record()
        var index = Data(repeating: 0xFF, count: 35025 * 12)
        // Human body 400, standing group 4, stored direction 3.
        let offset = (35000 + 20 + 3) * 12
        index.replaceSubrange(offset..<offset + 12, with: [0,0,0,0, UInt8(raw.count & 255),UInt8(raw.count >> 8),0,0,0,0,0,0])
        let assets = try AnimationAssets(index: index, data: raw, cacheLimit: 16)
        let north = try XCTUnwrap(assets.frame(body: 400, direction: 0))
        let west = try XCTUnwrap(assets.frame(body: 400, direction: 6))
        XCTAssertTrue(north.mirrored)
        XCTAssertFalse(west.mirrored)
        XCTAssertEqual(north.sprite.rgba, west.sprite.rgba)
        XCTAssertEqual(assets.cacheBytes, 16)
        XCTAssertNil(try assets.frame(body: 400, direction: 7))
        XCTAssertNil(try assets.frame(body: 9000, direction: 0))
        let uncached = try AnimationAssets(index: index, data: raw, cacheLimit: 0)
        XCTAssertNotNil(try uncached.frame(body: 400, direction: 6))
        XCTAssertEqual(uncached.cacheBytes, 0)
    }
}
