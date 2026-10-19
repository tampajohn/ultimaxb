import XCTest
@testable import UOCore

final class LightOcclusionTests: XCTestCase {
    private func tile(_ x: Int = 11, _ y: Int = 11, z: Int = 15, art: Int = 0x4001) -> WorldTile {
        WorldTile(x: x, y: y, z: z, art: art, hue: 0)
    }
    func testOnlyElevatedForegroundObjectsOcclude() {
        let occlusion = LightOcclusion(tiles: [tile()], visibility: WorldVisibility(), isOpaque: { _ in true })
        XCTAssertTrue(occlusion.blocks(x: 10, y: 10, z: 10))
        XCTAssertFalse(occlusion.blocks(x: 10, y: 10, z: 11))
        XCTAssertFalse(occlusion.blocks(x: 11, y: 10, z: 10))
        XCTAssertFalse(occlusion.blocks(x: 12, y: 12, z: 10))
    }
    func testCutawayIsLocalAndKeepsLowerWalls() {
        let visibility = WorldVisibility(ceiling: 30, ceilingCells: [.init(x: 11, y: 11)])
        let occlusion = LightOcclusion(tiles: [tile(z: 40), tile(z: 15), tile(21, 21, z: 40)],
                                      visibility: visibility, isOpaque: { _ in true })
        XCTAssertFalse(occlusion.blocks(x: 10, y: 10, z: 20), "Removed roof must not suppress interior light")
        XCTAssertTrue(occlusion.blocks(x: 10, y: 10, z: 10), "Visible lower wall still occludes")
        XCTAssertTrue(occlusion.blocks(x: 20, y: 20, z: 20), "Other building remains opaque")
    }
    func testTerrainEffectsAndNonOpaqueArtDoNotOcclude() {
        var effect = tile(); effect.effectAge = 0
        var gump = tile(); gump.effectGump = 100
        let occlusion = LightOcclusion(tiles: [tile(art: 1), effect, gump, tile(art: 0x4002)],
                                      visibility: WorldVisibility(), isOpaque: { $0 != 2 })
        XCTAssertFalse(occlusion.blocks(x: 10, y: 10, z: 0))
    }
}
