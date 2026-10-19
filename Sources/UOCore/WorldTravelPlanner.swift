import Foundation

/// Search the actual map to the destination, including bridge surfaces and elevation.
/// Chunk snapshots bound asset expansion; no speculative water-crossing graph edges.
public final class WorldTravelPlanner {
    public struct Attempt:Sendable {
        public let strategy:String
        public let statistics:WalkPath.SearchStatistics
    }
    public private(set) var attempts:[Attempt]=[]
    private let assets:ClientAssets
    private let ghost:Bool
    private var maps:[Int:NavigationMap]=[:],order:[Int]=[]
    public init(assets:ClientAssets,ghost:Bool = false) { self.assets=assets; self.ghost=ghost }
    private func map(_ point:WalkPoint)throws->NavigationMap {
        let bx=point.x/32,by=point.y/32,key=by*256+bx
        if let map=maps[key] { return map }
        let map=try NavigationMap(assets:assets,center:WalkPoint(x:bx*32+16,y:by*32+16,z:0),additional:[],radius:18,ghost:ghost)
        if order.count>=128 { maps.removeValue(forKey:order.removeFirst()) }
        maps[key]=map; order.append(key); return map
    }
    public func find(from:WalkPoint,x:Int,y:Int,adjacent:Bool = false,cancelled:()->Bool = { false })throws->[WalkPoint]? {
        guard (0..<assets.width).contains(x),(0..<assets.height).contains(y) else { return nil }
        attempts=[]
        // Give road preference a bounded first pass, then search for connectivity
        // without road penalties. Coastal detours can otherwise consume the
        // entire search exploring cheap roads on the wrong side of a barrier.
        for (strategy,limit,heuristic) in [("roads",100_000,3),("connectivity",300_000,3)] {
            let route=try WalkPath.find(from:from,x:x,y:y,adjacent:adjacent,limit:limit,heuristicWeight:heuristic,travelCost:{ point in
                strategy == "roads" ? ((try? self.map(point).travelCost(point)) ?? 3) : 1
            },report:{ self.attempts.append(Attempt(strategy:strategy,statistics:$0)) }) { point,direction in
                if cancelled() { throw CancellationError() }
                return try self.map(point).step(from:point,direction:direction)
            }
            if let route { return route }
            // Exhaustion means the reachable component was fully explored;
            // changing costs cannot make an island or enclosed tile reachable.
            if attempts.last?.statistics.outcome == .exhausted { return nil }
        }
        // Coastal traps are often cheap to diagnose from the destination.
        // Enumerate all surface levels and validate each incoming edge using
        // forward collision, preserving one-way drops and bridge heights.
        var goals:[WalkPoint]=[]
        let radius=adjacent ? 1 : 0
        for gx in (x-radius)...(x+radius) {
            for gy in (y-radius)...(y+radius) {
                let point=WalkPoint(x:gx,y:gy,z:0)
                goals += try map(point).candidateStandingPoints(x:gx,y:gy)
            }
        }
        let reverse=try ReverseWalkSearch.find(from:from,goals:goals,limit:60_000) { current in
            if cancelled() { throw CancellationError() }
            var incoming:[WalkPoint]=[]
            for (direction,delta) in WalkPath.directions.enumerated() {
                let px=current.x-delta.0,py=current.y-delta.1
                guard (0..<self.assets.width).contains(px),(0..<self.assets.height).contains(py) else { continue }
                let local=try self.map(WalkPoint(x:px,y:py,z:0))
                var candidates=local.candidateStandingPoints(x:px,y:py)
                // The authoritative starting elevation can be dynamic and absent
                // from the static surface list.
                if px==from.x && py==from.y { candidates.append(from) }
                for previous in candidates where local.step(from:previous,direction:UInt8(direction))==current {
                    incoming.append(previous)
                }
            }
            return incoming
        }
        attempts.append(Attempt(strategy:"destination_connectivity",statistics:reverse.statistics))
        return reverse.route
    }
}
