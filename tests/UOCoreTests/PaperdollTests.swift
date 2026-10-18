import XCTest
@testable import UOCore

final class PaperdollTests: XCTestCase {
    func testInstalledMaleAndFemaleEquipment() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("uo1998-client")
        guard FileManager.default.fileExists(atPath: directory.path) else { throw XCTSkip("Local assets absent") }
        let assets = try ClientAssets(directory: directory)
        let equipment = [EquippedItem(serial: 1, graphic: 3937, layer: 1, owner: 42),
                         EquippedItem(serial: 2, graphic: 5903, layer: 3, owner: 42, hue: 1859),
                         EquippedItem(serial: 3, graphic: 5433, layer: 4, owner: 42, hue: 1850),
                         EquippedItem(serial: 4, graphic: 8059, layer: 17, owner: 42, hue: 1408),
                         EquippedItem(serial: 5, graphic: 3701, layer: 21, owner: 42),
                         EquippedItem(serial: 6, graphic: 3937, layer: 1, owner: 99)]
        for body in [400,401] {
            let layers = try Paperdoll.layers(assets: assets, body: body, hue: 1002, owner: 42, equipment: equipment)
            XCTAssertEqual(layers.count, 6)
            XCTAssertEqual(layers.last?.item?.layer, 21)
            XCTAssertFalse(layers.contains { $0.item?.owner == 99 })
            let background = try XCTUnwrap(assets.gumps?.sprite(2000))
            var pixels = background.rgba
            for layer in layers {
                let sprite = layer.sprite
                for y in 0..<sprite.height where y+19 < background.height {
                    for x in 0..<sprite.width where x+8 < background.width {
                        let src = (y*sprite.width+x)*4, dst = ((y+19)*background.width+x+8)*4
                        if sprite.rgba[src+3] != 0 { pixels.replaceSubrange(dst..<dst+4, with: sprite.rgba[src..<src+4]) }
                    }
                }
            }
            if let output = ProcessInfo.processInfo.environment["UO_PAPERDOLL_PREVIEW"] {
                try Frame(width: background.width, height: background.height, rgba: pixels,
                    landCount: 0, staticCount: 0, missingCount: 0, huedCount: 0).writeBMP(to: URL(fileURLWithPath: output+"-\(body).bmp"))
            }
        }
    }
}
