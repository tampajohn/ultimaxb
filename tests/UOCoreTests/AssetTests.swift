import Foundation
import XCTest
@testable import UOCore

final class AssetTests: XCTestCase {
    func testDrawOrderKeepsDifferentCellsTogetherBeforeSortingHeight() {
        let wall = WorldTile(x: 10, y: 11, z: 20, art: 0x4001, hue: 0)
        let ground = WorldTile(x: 11, y: 10, z: 0, art: 4, hue: 0)
        let entries = [DrawEntry(tile: ground, priority: -2, originalIndex: 0),
                       DrawEntry(tile: wall, priority: 21, originalIndex: 1)]
        XCTAssertEqual(entries.sorted(by: DrawEntry.precedes).first?.tile.art, 0x4001)
    }

    func testDrawOrderUsesPriorityWithinCellAndPreservesStaticTies() {
        let land = WorldTile(x: 10, y: 10, z: 20, art: 4, hue: 0)
        let bridge = WorldTile(x: 10, y: 10, z: 19, art: 0x4001, hue: 0)
        let entries = [DrawEntry(tile: bridge, priority: 20, originalIndex: 2),
                       DrawEntry(tile: land, priority: 18, originalIndex: 0),
                       DrawEntry(tile: bridge, priority: 20, originalIndex: 1)]
        XCTAssertEqual(entries.sorted(by: DrawEntry.precedes).map(\.originalIndex), [0, 1, 2])
    }

    func testStaticPriorityReadsBackgroundFlagAndHeight() throws {
        try withClient { root in
            var metadata = Data(repeating: 0, count: 512 * 836 + 1188)
            let offset = 512 * 836 + 4
            metadata[offset] = 1 // Background flag on static 0.
            metadata[offset + 37 + 16] = 20 // Nonzero height on static 1.
            try metadata.write(to: root.appendingPathComponent("TILEDATA.MUL"))
            let assets = try ClientAssets(directory: root)
            XCTAssertEqual(try assets.drawPriority(WorldTile(x: 0, y: 0, z: 10, art: 0x4000, hue: 0)), 9)
            XCTAssertEqual(try assets.drawPriority(WorldTile(x: 0, y: 0, z: 10, art: 0x4001, hue: 0)), 11)
        }
    }
    func testTexturedTrianglesCoverSharedEdgeWithoutCracks() {
        let texture = Sprite(width: 1, height: 1, rgba: [255, 0, 0, 255])
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let a = TerrainVertex(x: 0, y: 0, u: 0, v: 0)
        let b = TerrainVertex(x: 16, y: 0, u: 1, v: 0)
        let c = TerrainVertex(x: 16, y: 16, u: 1, v: 1)
        let d = TerrainVertex(x: 0, y: 16, u: 0, v: 1)
        TerrainRasterizer.triangle(a, b, c, texture: texture, width: 16, height: 16, pixels: &pixels)
        TerrainRasterizer.triangle(a, c, d, texture: texture, width: 16, height: 16, pixels: &pixels)
        for p in stride(from: 0, to: pixels.count, by: 4) { XCTAssertEqual(pixels[p], 255) }
    }

    func testSlopedNeighborsShareProjectedEdge() {
        let texture = Sprite(width: 1, height: 1, rgba: [255, 0, 0, 255])
        var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
        TerrainRasterizer.draw(texture: texture, screenX: 40, screenY: 20, z: [0, 2, 2, 0],
                               width: 100, height: 100, pixels: &pixels)
        TerrainRasterizer.draw(texture: texture, screenX: 62, screenY: 42, z: [2, 4, 4, 2],
                               width: 100, height: 100, pixels: &pixels)
        for x in 40..<62 {
            let y = 95 - x
            XCTAssertEqual(pixels[(y * 100 + x) * 4], 255, "Crack at \(x),\(y)")
        }
    }

    func testInvisibleLandMarkersAreSkipped() throws {
        try withClient { root in
            let client = try ClientAssets(directory: root)
            let frame = try WorldRenderer.render(client, x: 0, y: 0, width: 32, height: 32)
            XCTAssertEqual(frame.landCount, 0)
            for p in stride(from: 0, to: frame.rgba.count, by: 4) {
                XCTAssertEqual(Array(frame.rgba[p..<p + 3]), [16, 22, 27])
            }
        }
    }

    func testTerrainTextureDecodeAndSharedCacheBudget() throws {
        try withClient { root in
            try Data(repeating: 0, count: 512 * 836).write(to: root.appendingPathComponent("TILEDATA.MUL"))
            try words([0, 0, 8192, 0, 0, 0]).write(to: root.appendingPathComponent("TEXIDX.MUL"))
            try words(Array(repeating: 0x03E0, count: 4096)).write(to: root.appendingPathComponent("TEXMAPS.MUL"))
            let client = try ClientAssets(directory: root, cacheLimit: 16384)
            _ = try client.sprite(0)
            let texture = try XCTUnwrap(client.terrainTexture(land: 4))
            XCTAssertEqual(texture.width, 64)
            XCTAssertEqual(texture.height, 64)
            XCTAssertEqual(Array(texture.rgba.prefix(4)), [0, 255, 0, 255])
            XCTAssertEqual(client.cacheBytes, 16384)
            _ = try client.sprite(0)
            XCTAssertEqual(client.cacheBytes, 44 * 44 * 4)
        }
    }

    func words(_ values: [Int]) -> Data {
        Data(values.flatMap { [UInt8($0 & 255), UInt8(($0 >> 8) & 255)] })
    }
    func testUnalignedLittleEndianAndBounds() throws {
        let b = Bytes(Data([9, 0x78, 0x56, 0x34, 0x12, 0xFB]))
        XCTAssertEqual(try b.u32(1), 0x12345678)
        XCTAssertEqual(try b.i8(5), -5)
        XCTAssertThrowsError(try b.u32(3))
        XCTAssertThrowsError(try b.u8(-1))
    }
    func testLandDiamondKeepsBlackOpaque() throws {
        let sprite = try ArtDecoder.land(Bytes(Data(repeating: 0, count: 2024)))
        XCTAssertEqual(sprite.rgba.enumerated().filter { $0.offset % 4 == 3 && $0.element == 255 }.count, 1012)
        XCTAssertEqual(sprite.rgba[21 * 4 + 3], 255)
        XCTAssertEqual(sprite.rgba[20 * 4 + 3], 0)
        XCTAssertThrowsError(try ArtDecoder.land(Bytes(Data(repeating: 0, count: 2023))))
    }
    func testStaticOffsetsTransparencyAndMalformedRuns() throws {
        let raw = words([0, 0, 4, 2, 0, 6, 1, 2, 0x7C00, 0, 0, 0, 0, 0])
        let sprite = try ArtDecoder.item(Bytes(raw))
        XCTAssertEqual(sprite.width, 4)
        XCTAssertEqual(sprite.height, 2)
        XCTAssertEqual(Array(sprite.rgba[4..<8]), [255, 0, 0, 255])
        XCTAssertEqual(sprite.rgba[11], 0)
        XCTAssertTrue(sprite.rgba[16...].allSatisfy { $0 == 0 })
        XCTAssertThrowsError(try ArtDecoder.item(Bytes(raw.dropLast(2))))
        XCTAssertThrowsError(try ArtDecoder.item(Bytes(words([0, 0, 1, 1, 0, 1, 1, 0x7FFF, 0]))))
    }
    func testBMPHeaderPaddingAndChannels() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bmp")
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = Frame(width: 1, height: 1, rgba: [255, 0, 0, 255], landCount: 0, staticCount: 0, missingCount: 0, huedCount: 0)
        try frame.writeBMP(to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 58)
        XCTAssertEqual(Array(data.suffix(4)), [0, 0, 255, 0])
    }

    func testNetworkGroundItemDrawsAndDisappearsWithoutChangingStaticAssets() throws {
        try withClient { root in
            // One green pixel in a static-art RLE record, referenced by ID 0.
            let art = words([0, 0, 1, 1, 0, 0, 1, 0x03E0, 0, 0])
            try art.write(to: root.appendingPathComponent("ART.MUL"))
            var index = Data(repeating: 0xFF, count: (0x4000 + 1) * 12)
            index.replaceSubrange(0x4000 * 12..<(0x4000 + 1) * 12,
                                  with: words([0, 0, art.count, 0, 0, 0]))
            try index.write(to: root.appendingPathComponent("ARTIDX.MUL"))
            let assets = try ClientAssets(directory: root)
            let before = try WorldRenderer.render(assets, x: 10, y: 10, width: 100, height: 100)
            let tile = WorldTile(x: 10, y: 10, z: 0, art: 0x4000, hue: 0)
            let during = try WorldRenderer.render(assets, x: 10, y: 10, width: 100, height: 100, groundItems: [tile])
            let after = try WorldRenderer.render(assets, x: 10, y: 10, width: 100, height: 100)
            XCTAssertEqual(during.staticCount, 1)
            XCTAssertEqual(Array(during.rgba[(93 * 100 + 50) * 4..<(93 * 100 + 50) * 4 + 4]), [0, 255, 0, 255])
            XCTAssertNotEqual(before.rgba, during.rgba)
            XCTAssertEqual(before.rgba, after.rgba)
        }
    }

    func withClient(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func sparse(_ name: String, size: Int) throws -> FileHandle {
            let url = root.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(size))
            return handle
        }
        let map = try sparse("MAP0.MUL", size: 77_070_336)
        // Tile (8,0) lives in block 512, not block 1.
        try map.seek(toOffset: 512 * 196 + 4)
        try map.write(contentsOf: Data([1, 0, 0xFB]))
        try map.close()
        let index = try sparse("STAIDX0.MUL", size: 393_216 * 12)
        try index.close()
        try Data().write(to: root.appendingPathComponent("STATICS0.MUL"))
        try words([0, 0, 2024, 0, 0, 0, 2024, 0, 2024, 0, 0, 0])
            .write(to: root.appendingPathComponent("ARTIDX.MUL"))
        try words(Array(repeating: 0x7C00, count: 1012) + Array(repeating: 0x001F, count: 1012))
            .write(to: root.appendingPathComponent("ART.MUL"))
        try body(root)
    }

    func testMapBlockOrderSignedElevationAndBounds() throws {
        try withClient { root in
            let client = try ClientAssets(directory: root)
            let tiles = try client.region(x: 8, y: 0, radius: 0)
            XCTAssertEqual(tiles.count, 1)
            XCTAssertEqual(tiles[0].art, 1)
            XCTAssertEqual(tiles[0].z, -5)
            XCTAssertThrowsError(try client.region(x: -1, y: 0, radius: 0))
            XCTAssertThrowsError(try client.region(x: 0, y: 4096, radius: 1))
        }
    }

    func testStaticAtBlockBoundaryAndFileOffsetZeroIsNotDropped() throws {
        try withClient { root in
            // A static at local (0,0) in world block (1,1), stored at byte zero.
            try Data([1, 0, 0, 0, 40, 0, 0]).write(to: root.appendingPathComponent("STATICS0.MUL"))
            let index = try FileHandle(forWritingTo: root.appendingPathComponent("STAIDX0.MUL"))
            try index.seek(toOffset: UInt64((512 + 1) * 12))
            try index.write(contentsOf: words([0, 0, 7, 0, 0, 0]))
            try index.close()
            let client = try ClientAssets(directory: root)
            let tiles = try client.region(x: 8, y: 8, radius: 0)
            let item = try XCTUnwrap(tiles.first(where: \.isStatic))
            XCTAssertEqual(item.x, 8)
            XCTAssertEqual(item.y, 8)
            XCTAssertEqual(item.z, 40)
            XCTAssertEqual(item.art, 0x4001)
            XCTAssertEqual(tiles.count, 2)
        }
    }

    func testArtPatchOverridesAndCacheEviction() throws {
        try withClient { root in
            // VERDATA: count=1; file=4, art=1, offset=24, length=2024, extra=0.
            let header = words([1, 0, 4, 0, 1, 0, 24, 0, 2024, 0, 0, 0])
            try (header + words(Array(repeating: 0x03E0, count: 1012)))
                .write(to: root.appendingPathComponent("VERDATA.MUL"))
            let client = try ClientAssets(directory: root, cacheLimit: 44 * 44 * 4)
            XCTAssertEqual(client.artOverrideCount, 1)
            for id in [0, 1, 0, 1] {
                let sprite = try XCTUnwrap(client.sprite(id))
                XCTAssertEqual(Array(sprite.rgba[84..<88]), id == 0 ? [255, 0, 0, 255] : [0, 255, 0, 255])
                XCTAssertLessThanOrEqual(client.cacheBytes, client.cacheLimit)
            }
        }
    }
}
