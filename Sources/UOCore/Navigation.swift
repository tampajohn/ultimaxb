import Foundation

public struct WalkPoint: Hashable, Sendable {
    public let x:Int, y:Int, z:Int
    public init(x:Int,y:Int,z:Int) { self.x=x; self.y=y; self.z=z }
}
public enum WalkPath {
    public struct SearchStatistics:Sendable,Equatable {
        public enum Outcome:String,Sendable { case found, exhausted, budgetExceeded }
        public let outcome:Outcome
        public let expanded:Int, popped:Int
    }
    public static let directions = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)]
    /// Bounded A*. Each step costs one movement request, including diagonals.
    public static func find(from start:WalkPoint, x:Int, y:Int, adjacent:Bool = false, goalRadius:Int? = nil, goalZ:Int? = nil,
                            limit:Int = 4096, heuristicWeight:Int = 1, segmentLength:Int? = nil, travelCost:(WalkPoint)->Int = { _ in 1 }, report:((SearchStatistics)->Void)? = nil, step:(WalkPoint,UInt8)throws->WalkPoint?) rethrows -> [WalkPoint]? {
        func distance(_ p:WalkPoint)->Int { max(0,max(abs(p.x-x),abs(p.y-y))-max(0,goalRadius ?? (adjacent ? 1 : 0))) }
        // Equal-length eight-way routes can otherwise zigzag across open ground.
        // Prefer proximity to the requested line only as a tie-breaker; this
        // never makes a longer route outrank a shorter one.
        func deviation(_ p:WalkPoint)->Int {
            abs((p.x-start.x)*(y-start.y)-(p.y-start.y)*(x-start.x))
        }
        var open=WalkFrontier(),costs=[start:0],parents:[WalkPoint:WalkPoint]=[:],closed=Set<WalkPoint>()
        open.push(point:start,cost:0,score:distance(start)*max(1,heuristicWeight),distance:distance(start),deviation:0)
        var expanded=0,popped=0
        while expanded<max(0,limit) {
            guard let entry=open.pop() else {
                report?(SearchStatistics(outcome:.exhausted,expanded:expanded,popped:popped)); return nil
            }
            popped += 1
            let current=entry.point
            if closed.contains(current) || costs[current] != entry.cost { continue }
            let reached = distance(current) == 0 && (goalZ == nil || abs(current.z-goalZ!)<=16)
            let segmentReached = segmentLength.map { $0 > 0 && max(abs(current.x-start.x),abs(current.y-start.y)) >= $0 && distance(current) < distance(start) } ?? false
            if reached || segmentReached {
                var path:[WalkPoint] = [], node = current
                while let previous = parents[node] { path.append(node); node = previous }
                report?(SearchStatistics(outcome:.found,expanded:expanded,popped:popped))
                return path.reversed()
            }
            closed.insert(current); expanded += 1
            for direction in UInt8(0)...7 {
                guard let next = try step(current,direction), !closed.contains(next) else { continue }
                let cost = costs[current]!+max(1,travelCost(next))
                if cost < costs[next,default:Int.max] {
                    costs[next] = cost; parents[next] = current
                    open.push(point:next,cost:cost,score:cost+distance(next)*max(1,heuristicWeight),distance:distance(next),deviation:deviation(next))
                }
            }
        }
        report?(SearchStatistics(outcome:.budgetExceeded,expanded:expanded,popped:popped))
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
        public let ghostPassable:Bool
        public let openDoor:Bool
        public init(z:Int,height:Int,flags:Int,ghostPassable:Bool = false,openDoor:Bool = false) {
            self.z=z; self.height=height; self.flags=flags; self.ghostPassable=ghostPassable; self.openDoor=openDoor
        }
        /// Classic ghost exceptions remove obstruction, not supporting surfaces.
        /// Lightweight world items differ from baked map/multi components.
        public static func passableForGhost(graphic:Int,flags:Int,dynamic:Bool,weight:Int)->Bool {
            flags & 0x20000000 != 0 || [0x0692,0x06F5,0x06F6,0x0846,0x0873].contains(graphic) ||
                (dynamic && weight <= 90)
        }
    }
    public struct Cell {
        public let landZ:Int, lowZ:Int, landBlocked:Bool, surfaces:[Surface]
        public init(landZ:Int,lowZ:Int,landBlocked:Bool,surfaces:[Surface]) {
            self.landZ=landZ; self.lowZ=lowZ; self.landBlocked=landBlocked; self.surfaces=surfaces
        }
        public func standingZ(from:Int, ignoringDoors:Bool = false, ghost:Bool = false)->Int? {
            let surfaces = ignoringDoors ? surfaces.filter { $0.flags & 0x20000000 == 0 || $0.openDoor } : surfaces
            var candidates:[Int] = []
            if !landBlocked && lowZ <= from+8 && landZ >= from-20 { candidates.append(landZ) }
            for s in surfaces where s.flags & 0x600 != 0 && s.flags & 0x40 == 0 {
                let top = s.z + (s.flags & 0x400 != 0 ? s.height/2 : s.height)
                if top <= from+8 && top >= from-20 { candidates.append(top) }
            }
            return candidates.sorted(by:>).first { z in
                !surfaces.contains { s in
                    if ghost && s.ghostPassable { return false }
                    guard s.flags & 0x640 != 0 else { return false }
                    let top = s.z + (s.flags & 0x400 != 0 ? s.height/2 : (s.flags & 0x40 != 0 ? max(1,s.height) : s.height))
                    return top > z && s.z < z+16
                }
            }
        }
    }
    private struct XY:Hashable { let x:Int,y:Int }
    private var cells:[XY:Cell] = [:]
    private var roads:Set<XY> = []
    private let ghost:Bool
    public init(assets:ClientAssets,center:WalkPoint,additional:[WorldTile],radius:Int = 24,ghost:Bool = false) throws {
        self.ghost = ghost
        let tiles = try assets.region(x:center.x,y:center.y,radius:radius)
        let grouped = Dictionary(grouping:tiles + additional,by:{ XY(x:$0.x,y:$0.y) })
        var roadGraphics:[Int:Bool] = [:]
        for (xy,items) in grouped {
            guard abs(xy.x-center.x)<=radius, abs(xy.y-center.y)<=radius,
                  let land = items.first(where:{ !$0.isStatic }),xy.x+1<assets.width,xy.y+1<assets.height else { continue }
            let corners = try [land.z,assets.elevation(x:xy.x+1,y:xy.y),assets.elevation(x:xy.x+1,y:xy.y+1),assets.elevation(x:xy.x,y:xy.y+1)]
            let average = abs(corners[0]-corners[2]) <= abs(corners[1]-corners[3]) ? (corners[0]+corners[2])>>1 : (corners[1]+corners[3])>>1
            let flags = try assets.landFlags(graphic:land.art)
            let road:Bool
            if let cached=roadGraphics[land.art] { road=cached }
            else {
                let name=try assets.landName(graphic:land.art).lowercased()
                road=["road","cobblestone","pavers","flagstone"].contains(where:name.contains)
                roadGraphics[land.art]=road
            }
            if road { roads.insert(xy) }
            let surfaces = try items.filter(\.isStatic).map { tile in
                let graphic = tile.art-0x4000
                let flags = try assets.itemFlags(graphic:graphic)
                return Surface(z:tile.z,height:try assets.itemHeight(graphic:graphic),flags:flags,
                    ghostPassable:try Surface.passableForGhost(graphic:graphic,flags:flags,dynamic:tile.isDynamic,
                                                              weight:assets.itemWeight(graphic:graphic)),
                    openDoor:DoorOpeningWait.isOpenGraphic(graphic) == true)
            }
            cells[xy] = Cell(landZ:average,lowZ:corners.min()!,landBlocked:land.art<=2 || flags & 0xC0 != 0,surfaces:surfaces)
        }
    }
    /// Superset of elevations which standingZ can return. Incoming edges must
    /// still be validated with step; a surface can be obstructed at this height.
    public func candidateStandingPoints(x:Int,y:Int)->[WalkPoint] {
        guard let cell=cells[XY(x:x,y:y)] else { return [] }
        var heights=Set<Int>()
        if !cell.landBlocked { heights.insert(cell.landZ) }
        for surface in cell.surfaces where surface.flags & 0x600 != 0 && surface.flags & 0x40 == 0 {
            heights.insert(surface.z + (surface.flags & 0x400 != 0 ? surface.height/2 : surface.height))
        }
        return heights.sorted().map { WalkPoint(x:x,y:y,z:$0) }
    }
    public func travelCost(_ point:WalkPoint)->Int { roads.contains(XY(x:point.x,y:point.y)) ? 1 : 3 }
    public func standingPoint(x:Int,y:Int,fromZ:Int)->WalkPoint? {
        guard let z = cells[XY(x:x,y:y)]?.standingZ(from:fromZ,ghost:ghost) else { return nil }
        return WalkPoint(x:x,y:y,z:z)
    }
    public func step(from:WalkPoint,direction:UInt8, ignoringDoors:Bool = false)->WalkPoint? {
        let delta = WalkPath.directions[Int(direction&7)]
        let x=from.x+delta.0,y=from.y+delta.1
        guard let z=cells[XY(x:x,y:y)]?.standingZ(from:from.z, ignoringDoors:ignoringDoors,ghost:ghost) else { return nil }
        // Conservative corner clearance prevents routes through touching walls.
        if delta.0 != 0 && delta.1 != 0 {
            guard cells[XY(x:x,y:from.y)]?.standingZ(from:from.z, ignoringDoors:ignoringDoors,ghost:ghost) != nil,
                  cells[XY(x:from.x,y:y)]?.standingZ(from:from.z, ignoringDoors:ignoringDoors,ghost:ghost) != nil else { return nil }
        }
        return WalkPoint(x:x,y:y,z:z)
    }
}

/// Resolve roof art to a floor in its nearby footprint, not terrain behind the
/// building at the same screen pixel. Eaves often occupy an impassable wall cell.
public enum WalkDestination {
    public static func beneathRoof(_ roof:WalkPoint, footprint:[WalkPoint], player:WalkPoint,
                                   standing:(Int,Int)->WalkPoint?)->WalkPoint? {
        let nearby = Set(footprint + [roof]).filter {
            max(abs($0.x-roof.x),abs($0.y-roof.y)) <= 2 && abs($0.z-roof.z) <= 16
        }
        var connected:Set<WalkPoint> = [roof], queue = [roof]
        while let cell = queue.popLast() {
            for neighbor in nearby where !connected.contains(neighbor) &&
                abs(neighbor.x-cell.x)+abs(neighbor.y-cell.y) == 1 && abs(neighbor.z-cell.z)<=16 {
                connected.insert(neighbor); queue.append(neighbor)
            }
        }
        let cells = connected.sorted {
            let a = (max(abs($0.x-roof.x),abs($0.y-roof.y)),max(abs($0.x-player.x),abs($0.y-player.y)),$0.x,$0.y)
            let b = (max(abs($1.x-roof.x),abs($1.y-roof.y)),max(abs($1.x-player.x),abs($1.y-player.y)),$1.x,$1.y)
            return a < b
        }
        for cell in cells {
            if let floor = standing(cell.x,cell.y),floor.z < cell.z { return floor }
        }
        return nil
    }
}

private struct WalkFrontier {
    struct Entry {
        let point:WalkPoint,cost:Int,score:Int,distance:Int,deviation:Int,order:Int
        func precedes(_ b:Entry)->Bool { (score,distance,deviation,order)<(b.score,b.distance,b.deviation,b.order) }
    }
    private var entries:[Entry]=[]
    private var order=0
    mutating func push(point:WalkPoint,cost:Int,score:Int,distance:Int,deviation:Int) {
        entries.append(Entry(point:point,cost:cost,score:score,distance:distance,deviation:deviation,order:order)); order+=1
        var i=entries.count-1
        while i>0 { let parent=(i-1)/2; if !entries[i].precedes(entries[parent]) { break }; entries.swapAt(i,parent); i=parent }
    }
    mutating func pop()->Entry? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries.removeLast() }
        let first=entries[0]; entries[0]=entries.removeLast(); var i=0
        while i*2+1<entries.count {
            var child=i*2+1
            if child+1<entries.count && entries[child+1].precedes(entries[child]) { child+=1 }
            if !entries[child].precedes(entries[i]) { break }; entries.swapAt(i,child); i=child
        }
        return first
    }
}
