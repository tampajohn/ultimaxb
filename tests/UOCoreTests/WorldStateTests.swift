import Foundation
import XCTest
@testable import UOCore

final class WorldStateTests: XCTestCase {
    private func item(options: Int = 0, graphic: UInt16 = 0x0BD2, flags: UInt8 = 0x20) -> Data {
        var b = Data([0x1A, 0, 0])
        func word(_ v: UInt16) { b.append(UInt8(v >> 8)); b.append(UInt8(truncatingIfNeeded: v)) }
        b += Data(options & 1 != 0 ? [0xC0, 0, 0, 1] : [0x40, 0, 0, 1])
        word(graphic | (options & 2 != 0 ? 0x8000 : 0))
        if options & 2 != 0 { b.append(2) }
        if options & 1 != 0 { word(42) }
        word(1435 | (options & 4 != 0 ? 0x8000 : 0))
        word(1695 | (options & 8 != 0 ? 0x8000 : 0) | (options & 16 != 0 ? 0x4000 : 0))
        if options & 4 != 0 { b.append(3) }
        b.append(0xF6)
        if options & 8 != 0 { word(0x0123) }
        if options & 16 != 0 { b.append(flags) }
        b[2] = UInt8(b.count)
        return b
    }
    func testGroundLightPatternSurvivesWorldTileConversion() throws {
        for options in [0, 4] {
            var world = WorldState()
            try world.apply(item(options: options, graphic: 0x0B20))
            let tile = try XCTUnwrap(world.groundTiles.first)
            XCTAssertEqual(tile.lightID, options == 0 ? 0 : 3)
        }
        let mapTile = WorldTile(x: 0, y: 0, z: 0, art: 0x4B20, hue: 0)
        XCTAssertNil(mapTile.lightID, "Map statics must retain their asset-defined light pattern")
    }
    func testAllOptionalFieldsAndTruncatedPayloads() throws {
        for options in 0..<32 {
            let packet = item(options: options)
            let decoded = try GroundItem.decode(packet)
            XCTAssertEqual(decoded.serial, 0x40000001)
            XCTAssertEqual(decoded.graphic, 0x0BD2 + (options & 2 != 0 ? 2 : 0))
            XCTAssertEqual(decoded.amount, options & 1 != 0 ? 42 : 1)
            XCTAssertEqual(decoded.x, 1435)
            XCTAssertEqual(decoded.y, 1695)
            XCTAssertEqual(decoded.z, -10)
            XCTAssertEqual(decoded.direction, options & 4 != 0 ? 3 : 0)
            XCTAssertEqual(decoded.hue, options & 8 != 0 ? 0x123 : 0)
            XCTAssertEqual(decoded.flags, options & 16 != 0 ? 0x20 : 0)
            for end in 3..<packet.count {
                var truncated = Data(packet.prefix(end))
                truncated[2] = UInt8(end)
                XCTAssertThrowsError(try GroundItem.decode(truncated))
            }
        }
    }
    func testUpdatesReplaceBySerialAndRemovalTransitions() throws {
        for opcode: UInt8 in [0x1D, 0x25, 0x2E, 0x3C] {
            var world = WorldState()
            XCTAssertTrue(try world.apply(item()))
            XCTAssertFalse(try world.apply(item()))
            XCTAssertTrue(try world.apply(item(graphic: 0x0BD3)))
            XCTAssertEqual(world.groundTiles.count, 1)
            XCTAssertEqual(world.groundTiles[0].art, 0x4BD3)
            var removal: Data
            if opcode == 0x3C {
                removal = Data([0x3C, 0, 24, 0, 1, 0x40, 0, 0, 1])
                removal += Data(repeating: 0, count: 15)
            } else {
                removal = Data([opcode, 0x40, 0, 0, 1])
                removal += Data(repeating: 0, count: opcode == 0x1D ? 0 : (opcode == 0x25 ? 15 : 10))
            }
            XCTAssertTrue(try world.apply(removal))
            XCTAssertTrue(world.groundTiles.isEmpty)
        }
    }
    func testHiddenItemsAndMultisDoNotBecomeOrdinarySprites() throws {
        var world = WorldState()
        try world.apply(item(options: 16, flags: 0x80))
        XCTAssertTrue(world.groundTiles.isEmpty)
        try world.apply(item(graphic: 0x4001))
        XCTAssertTrue(world.groundTiles.isEmpty)
        XCTAssertEqual(world.items.count, 1)
    }
}
