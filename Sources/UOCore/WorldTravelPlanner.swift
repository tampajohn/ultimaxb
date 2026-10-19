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
        return nil
    }
}
