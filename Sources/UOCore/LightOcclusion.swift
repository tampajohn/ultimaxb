import Foundation

/// Classic foreground-cell light occlusion (CrossUO GameScreen::AddLight).
/// Only visible opaque statics/items participate; removed ceilings cannot
/// suppress interior lights. This is sprite occlusion, not ray-traced shadows.
struct LightOcclusion {
    private var highest: [WorldVisibility.Cell: Int] = [:]

    init(tiles: [WorldTile], visibility: WorldVisibility,
         isOpaque: (Int) throws -> Bool) rethrows {
        for tile in tiles where tile.isStatic && tile.effectAge == nil && tile.effectGump == nil {
            guard !visibility.hides(z: tile.z, x: tile.x, y: tile.y),
                  try isOpaque(tile.art - 0x4000) else { continue }
            let cell = WorldVisibility.Cell(x: tile.x, y: tile.y)
            highest[cell] = max(highest[cell] ?? tile.z, tile.z)
        }
    }

    func blocks(x: Int, y: Int, z: Int) -> Bool {
        guard let height = highest[WorldVisibility.Cell(x: x + 1, y: y + 1)] else { return false }
        return height >= z + 5
    }
}
