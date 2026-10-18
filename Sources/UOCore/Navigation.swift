import Foundation

public struct WalkPoint: Hashable {
    public let x:Int, y:Int, z:Int
    public init(x:Int,y:Int,z:Int) { self.x=x; self.y=y; self.z=z }
}
public enum WalkPath {
    public static let directions = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)]
    /// Bounded A*. Each step costs one movement request, including diagonals.
    public static func find(from start:WalkPoint, x:Int, y:Int, adjacent:Bool = false, goalZ:Int? = nil,
                            limit:Int = 4096, segmentLength:Int? = nil, step:(WalkPoint,UInt8)throws->WalkPoint?) rethrows -> [WalkPoint]? {
        func distance(_ p:WalkPoint)->Int { max(0,max(abs(p.x-x),abs(p.y-y))-(adjacent ? 1 : 0)) }
        // Equal-length eight-way routes can otherwise zigzag across open ground.
        // Prefer proximity to the requested line only as a tie-breaker; this
        // never makes a longer route outrank a shorter one.
        func deviation(_ p:WalkPoint)->Int {
            abs((p.x-start.x)*(y-start.y)-(p.y-start.y)*(x-start.x))
        }
        var open = [start], costs = [start:0], parents:[WalkPoint:WalkPoint] = [:], closed = Set<WalkPoint>()
        for _ in 0..<max(0,limit) {
            guard let index = open.indices.min(by:{ (costs[open[$0]]!+distance(open[$0]),distance(open[$0]),deviation(open[$0])) < (costs[open[$1]]!+distance(open[$1]),distance(open[$1]),deviation(open[$1])) }) else { return nil }
            let current = open.remove(at:index)
            let reached = distance(current) == 0 && (goalZ == nil || abs(current.z-goalZ!)<=16)
            let segmentReached = segmentLength.map { $0 > 0 && max(abs(current.x-start.x),abs(current.y-start.y)) >= $0 && distance(current) < distance(start) } ?? false
            if reached || segmentReached {
                var path:[WalkPoint] = [], node = current
                while let previous = parents[node] { path.append(node); node = previous }
                return path.reversed()
            }
            closed.insert(current)
            for direction in UInt8(0)...7 {
                guard let next = try step(current,direction), !closed.contains(next) else { continue }
                let cost = costs[current]!+1
                if cost < costs[next,default:Int.max] {
                    if costs[next] == nil { open.append(next) }
                    costs[next] = cost; parents[next] = current
                }
            }
        }
        return nil
    }
    public static func direction(from:WalkPoint,to:WalkPoint)->UInt8? {
        directions.firstIndex { from.x+$0.0 == to.x && from.y+$0.1 == to.y }.map(UInt8.init)
    }
}

/// A local collision snapshot. Server denial always takes precedence.
public final class NavigationMap {
    public struct Surface {
        public let z:Int, height:Int, flags:Int
        public init(z:Int,height:Int,flags:Int) { self.z=z; self.height=height; self.flags=flags }
    }
    public struct Cell {
        public let landZ:Int, lowZ:Int, landBlocked:Bool, surfaces:[Surface]
        public init(landZ:Int,lowZ:Int,landBlocked:Bool,surfaces:[Surface]) {
            self.landZ=landZ; self.lowZ=lowZ; self.landBlocked=landBlocked; self.surfaces=surfaces
        }
        public func standingZ(from:Int)->Int? {
            var candidates:[Int] = []
            if !landBlocked && lowZ <= from+8 && landZ >= from-20 { candidates.append(landZ) }
            for s in surfaces where s.flags & 0x600 != 0 && s.flags & 0x40 == 0 {
                let top = s.z + (s.flags & 0x400 != 0 ? s.height/2 : s.height)
                if top <= from+8 && top >= from-20 { candidates.append(top) }
            }
            return candidates.sorted(by:>).first { z in
                !surfaces.contains { s in
                    guard s.flags & 0x640 != 0 else { return false }
                    let top = s.z + (s.flags & 0x400 != 0 ? s.height/2 : (s.flags & 0x40 != 0 ? max(1,s.height) : s.height))
                    return top > z && s.z < z+16
                }
            }
        }
    }
    private struct XY:Hashable { let x:Int,y:Int }
    private var cells:[XY:Cell] = [:]
    public init(assets:ClientAssets,center:WalkPoint,additional:[WorldTile],radius:Int = 24) throws {
        let tiles = try assets.region(x:center.x,y:center.y,radius:radius)
        let grouped = Dictionary(grouping:tiles + additional,by:{ XY(x:$0.x,y:$0.y) })
        for (xy,items) in grouped {
            guard abs(xy.x-center.x)<=radius, abs(xy.y-center.y)<=radius,
                  let land = items.first(where:{ !$0.isStatic }),xy.x+1<assets.width,xy.y+1<assets.height else { continue }
            let corners = try [land.z,assets.elevation(x:xy.x+1,y:xy.y),assets.elevation(x:xy.x+1,y:xy.y+1),assets.elevation(x:xy.x,y:xy.y+1)]
            let average = abs(corners[0]-corners[2]) <= abs(corners[1]-corners[3]) ? (corners[0]+corners[2])>>1 : (corners[1]+corners[3])>>1
            let flags = try assets.landFlags(graphic:land.art)
            let surfaces = try items.filter(\.isStatic).map { tile in
                Surface(z:tile.z,height:try assets.itemHeight(graphic:tile.art-0x4000),flags:try assets.itemFlags(graphic:tile.art-0x4000))
            }
            cells[xy] = Cell(landZ:average,lowZ:corners.min()!,landBlocked:land.art<=2 || flags & 0xC0 != 0,surfaces:surfaces)
        }
    }
    public func step(from:WalkPoint,direction:UInt8)->WalkPoint? {
        let delta = WalkPath.directions[Int(direction&7)]
        let x=from.x+delta.0,y=from.y+delta.1
        guard let z=cells[XY(x:x,y:y)]?.standingZ(from:from.z) else { return nil }
        // Conservative corner clearance prevents routes through touching walls.
        if delta.0 != 0 && delta.1 != 0 {
            guard cells[XY(x:x,y:from.y)]?.standingZ(from:from.z) != nil,
                  cells[XY(x:from.x,y:y)]?.standingZ(from:from.z) != nil else { return nil }
        }
        return WalkPoint(x:x,y:y,z:z)
    }
}
