import Foundation
import UOCore

/// Local asset regression: no server connection and no character movement.
@main struct Check {
    static func main() throws {
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let start=WalkPoint(x:1451,y:1654,z:10)
        let inns=TravelDestination.cities.filter { ["Minoc","Vesper","Yew","Trinsic"].contains($0.name) }.map { ($0.name,$0.x,$0.y,false) }
        let banks=[("Minoc bank",2503,554,true),("Vesper bank",2880,683,true)]
        for (name,x,y,adjacent) in inns+banks {
            let planner=WorldTravelPlanner(assets:assets)
            let began=Date()
            guard let route=try planner.find(from:start,x:x,y:y,adjacent:adjacent),let end=route.last else {
                fatalError("Britain to \(name) failed: \(planner.attempts)")
            }
            precondition(max(abs(end.x-x),abs(end.y-y)) <= (adjacent ? 1 : 0))
            var previous=start,chunkX = -1,chunkY = -1,collision:NavigationMap?
            for next in route {
                let bx=previous.x/32,by=previous.y/32
                if bx != chunkX || by != chunkY {
                    collision=try NavigationMap(assets:assets,center:WalkPoint(x:bx*32+16,y:by*32+16,z:0),additional:[],radius:18)
                    chunkX=bx;chunkY=by
                }
                guard let direction=WalkPath.direction(from:previous,to:next),collision?.step(from:previous,direction:direction)==next else {
                    fatalError("Invalid route step \(previous) -> \(next)")
                }
                previous=next
            }
            let counts=planner.attempts.map { "\($0.strategy):\($0.statistics.outcome.rawValue)/\($0.statistics.expanded)" }.joined(separator:", ")
            print("Britain -> \(name): \(route.count) collision-valid steps, \(counts), \(String(format:"%.2f",Date().timeIntervalSince(began)))s")
        }
    }
}
