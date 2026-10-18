import Foundation
import XCTest
@testable import UOCore

final class WalkingDepthTests: XCTestCase {
    func testWalkingAwayDoesNotDisappearUnderSourceFloor() throws {
        try AssetTests().withClient { root in
            // A red/green two-pixel mobile foot over a blue source-cell land tile.
            let map = try FileHandle(forWritingTo: root.appendingPathComponent("MAP0.MUL"))
            let x = 11, y = 10
            let block = (x / 8) * 512 + y / 8
            try map.seek(toOffset: UInt64(block * 196 + 4 + ((y % 8) * 8 + x % 8) * 3))
            try map.write(contentsOf: Data([3,0,0]))
            try map.close()
            let blueLand = AssetTests().words(Array(repeating: 0x001F, count: 1012))
            try blueLand.write(to: root.appendingPathComponent("ART.MUL"))
            var artIndex = Data(repeating: 0xFF, count: 4 * 12)
            artIndex.replaceSubrange(36..<48, with: [0,0,0,0,0xE8,7,0,0,0,0,0,0])
            try artIndex.write(to: root.appendingPathComponent("ARTIDX.MUL"))
            let raw = AnimationTests().record()
            var animationIndex = Data(repeating: 0xFF, count: 35025 * 12)
            for entry in [35000,35020] { // facing 3, walking and standing
                animationIndex.replaceSubrange(entry * 12..<entry * 12 + 12,
                    with: [0,0,0,0,UInt8(raw.count & 255),UInt8(raw.count >> 8),0,0,0,0,0,0])
            }
            try animationIndex.write(to: root.appendingPathComponent("ANIM.IDX"))
            try raw.write(to: root.appendingPathComponent("ANIM.MUL"))
            let assets = try ClientAssets(directory: root)
            let player = WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 0)
            let pose = MobilePresentation(x: 10.75, y: 10, z: 0, walking: true, frame: 0)
            let frame = try WorldRenderer.render(assets, x: 10, y: 10, width: 128, height: 128,
                                                mobiles: [player], mobilePresentations: [1: pose])
            // Foot anchor: round(64 + .75*22) - 1 = 80; y = round(64 + .75*22)+20 = 101.
            let pixel = (101 * 128 + 80) * 4
            XCTAssertEqual(Array(frame.rgba[pixel..<pixel+8]), [255,0,0,255,0,255,0,255])
        }
    }
}
