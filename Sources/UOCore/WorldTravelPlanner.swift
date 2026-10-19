import Foundation

/// Search the actual map to the destination, including bridge surfaces and elevation.
/// Chunk snapshots bound asset expansion; no speculative water-crossing graph edges.
public final class WorldTravelPlanner {
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
        // Weighted heuristic avoids exploring every side road on long journeys;
        // all returned individual steps still satisfy real collision checks.
        return try WalkPath.find(from:from,x:x,y:y,adjacent:adjacent,limit:400_000,heuristicWeight:3,travelCost:{ point in
            (try? self.map(point).travelCost(point)) ?? 3
        }) { point,direction in
            if cancelled() { throw CancellationError() }
            return try self.map(point).step(from:point,direction:direction)
        }
    }
}
