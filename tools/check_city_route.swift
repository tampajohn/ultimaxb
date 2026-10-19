import Foundation
import UOCore
@main struct CheckCityRoute {
    static func main() throws {
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        var current=WalkPoint(x:2477,y:411,z:15),visited=Set<WalkPoint>(),steps=0
        for segment in 0..<100 {
            let map=try NavigationMap(assets:assets,center:current,additional:[],radius:48)
            guard let path=WalkPath.find(from:current,x:2771,y:976,segmentLength:32,travelCost:map.travelCost,step:{map.step(from:$0,direction:$1)}) else {
                print("Static route stops at \(current.x),\(current.y),\(current.z) after \(steps) steps (segment \(segment)); needs wider planning or a waypoint")
                return
            }
            if path.isEmpty { print("Static Minoc–Vesper route reached destination in \(steps) steps"); return }
            current=path.last!; steps += path.count
            guard visited.insert(current).inserted else { fatalError("Route loop") }
        }
        fatalError("Route exceeded segment limit")
    }
}
