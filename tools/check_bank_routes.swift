import Foundation
import UOCore

/// Requires locally installed assets; never opens a network connection or moves
/// a character. Checks complete static routes, not banker availability or range.
@main struct Check {
    static func main() throws {
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        for (name,x,y) in [("Minoc",2503,554),("Britain",1427,1685),("Vesper",2880,683),("Jhelom",1319,3775),("Skara Brae",591,2142)] {
            let town=TravelDestination.cities.first { $0.name==name }!
            let start=WalkPoint(x:town.x,y:town.y,z:try assets.elevation(x:town.x,y:town.y))
            let route=try WorldTravelPlanner(assets:assets).find(from:start,x:x,y:y,adjacent:true)
            guard let route,let end=route.last else { fatalError("No static route from \(name) inn to bank approach") }
            precondition(max(abs(end.x-x),abs(end.y-y))<=1)
            // Revalidate every step rather than accepting just the final coordinate.
            var previous=start
            for point in route {
                guard let direction=WalkPath.direction(from:previous,to:point) else { fatalError("Non-adjacent route step") }
                let map=try NavigationMap(assets:assets,center:previous,additional:[],radius:2)
                precondition(map.step(from:previous,direction:direction)==point)
                previous=point
            }
            print("\(name): \(route.count) collision-valid steps; bank approach \(end.x), \(end.y), \(end.z)")
        }
    }
}
