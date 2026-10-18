import Foundation

/// Local connected ceiling cutaway; never changes collision or server elevation.
public struct WorldVisibility: Equatable {
    public struct Cell: Hashable, Sendable {
        public let x: Int, y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }
    public let ceiling: Int?
    public let terrainCeiling: Int?
    public let ceilingCells: Set<Cell>?
    public let terrainCells: Set<Cell>?
    public init(ceiling: Int? = nil, terrainCeiling: Int? = nil,
                ceilingCells: Set<Cell>? = nil, terrainCells: Set<Cell>? = nil) {
        self.ceiling = ceiling; self.terrainCeiling = terrainCeiling
        self.ceilingCells = ceilingCells; self.terrainCells = terrainCells
    }
    /// Four-way adjacency avoids leaking across buildings which touch at a corner.
    static func connected(_ heights: [Cell: Int], seed: Cell) -> Set<Cell> {
        guard heights[seed] != nil else { return [] }
        var visited: Set<Cell> = [seed], queue = [seed], index = 0
        while index < queue.count {
            let cell = queue[index]; index += 1
            for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                let next = Cell(x: cell.x+dx, y: cell.y+dy)
                if !visited.contains(next), let z = heights[next], abs(z-heights[cell]!) <= 20 {
                    visited.insert(next); queue.append(next)
                }
            }
        }
        return visited
    }
    public static func around(player: WorldMobile, assets: ClientAssets, additionalTiles: [WorldTile] = []) throws -> WorldVisibility {
        let head = player.z + 14, seed = Cell(x: player.x, y: player.y)
        let cell = try assets.region(x: player.x, y: player.y, radius: 0) + additionalTiles.filter { $0.x == player.x && $0.y == player.y }
        var underTerrain = false, underRoof = false
        for tile in cell where tile.z > head {
            if !tile.isStatic && tile.art > 2 { underTerrain = true }
            if tile.isStatic, (try assets.itemFlags(graphic: tile.art-0x4000)) & (0x10000000 | 0x200) != 0 { underRoof = true }
        }
        guard underTerrain || underRoof else { return WorldVisibility() }
        var roofs: [Cell: Int] = [:], terrain: [Cell: Int] = [:]
        for tile in try assets.region(x: player.x, y: player.y, radius: 24) + additionalTiles where tile.z > head {
            let key = Cell(x: tile.x, y: tile.y)
            if !tile.isStatic && tile.art > 2 { terrain[key] = tile.z }
            if tile.isStatic, (try assets.itemFlags(graphic: tile.art-0x4000)) & (0x10000000 | 0x200) != 0 {
                roofs[key] = min(roofs[key] ?? tile.z, tile.z)
            }
        }
        let landCells = underTerrain ? connected(terrain, seed: seed) : []
        let roofCells = underRoof ? connected(roofs, seed: seed) : []
        return WorldVisibility(ceiling: head, terrainCeiling: underTerrain ? head : nil,
            ceilingCells: roofCells.union(landCells), terrainCells: landCells)
    }
    public func hidesTerrain(z: Int, x: Int? = nil, y: Int? = nil) -> Bool {
        guard let terrainCeiling, z >= terrainCeiling else { return false }
        if let terrainCells, let x, let y { return terrainCells.contains(Cell(x: x, y: y)) }
        return true
    }
    public func hides(z: Int, x: Int? = nil, y: Int? = nil) -> Bool {
        guard let ceiling, z >= ceiling else { return false }
        if let ceilingCells, let x, let y { return ceilingCells.contains(Cell(x: x, y: y)) }
        return true
    }
}
