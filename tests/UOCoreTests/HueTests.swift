import Foundation
import XCTest
@testable import UOCore

final class HueTests: XCTestCase {
    func testPaletteIndexAcrossGroupBoundaryAndAllIntensityLevels() throws {
        var data = Data(repeating: 0, count: 1416)
        for level in 0..<32 {
            // Ninth hue is a green ramp in the next group, after its header.
            let color = level << 5
            data[712 + level * 2] = UInt8(color & 255)
            data[713 + level * 2] = UInt8(color >> 8)
        }
        let table = HueTable(data)
        let palette = try XCTUnwrap(table.palette(9))
        for level in 0..<32 {
            let input = UInt8(level * 255 / 31)
            let color = palette.color(red: input, green: input, blue: input)
            XCTAssertEqual(color.0, 0)
            XCTAssertEqual(color.1, input)
            XCTAssertEqual(color.2, 0)
        }
        XCTAssertNil(try table.palette(0))
        XCTAssertNil(try table.palette(17))
        XCTAssertNil(try table.palette(0x4009))
        XCTAssertNil(try HueTable(Data(repeating: 0, count: 90)).palette(1))
    }
    func testPartialHuePreservesColoredPixels() throws {
        var data = Data(repeating: 0, count: 708)
        for i in 0..<32 { data[4 + i * 2] = 0x1F }
        let table = HueTable(data)
        for palette in [try XCTUnwrap(table.palette(0x8001)), try XCTUnwrap(table.palette(1, partial: true))] {
            let untouched = palette.color(red: 255, green: 0, blue: 0)
            XCTAssertEqual(untouched.0, 255)
            XCTAssertEqual(untouched.2, 0)
            let changed = palette.color(red: 128, green: 128, blue: 128)
            XCTAssertEqual(changed.0, 0)
            XCTAssertEqual(changed.2, 255)
        }
        let full = try XCTUnwrap(table.palette(1)).color(red: 255, green: 0, blue: 0)
        XCTAssertEqual(full.0, 0)
        XCTAssertEqual(full.2, 255)
    }
}
