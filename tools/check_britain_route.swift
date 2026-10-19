import Foundation
import UOCore
@main struct CheckBritainRoute {
 static func main() throws {
    let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
    let start=WalkPoint(x:2477,y:411,z:15),planner=WorldTravelPlanner(assets:assets)
    let began=Date()
    guard let route=try planner.find(from:start,x:1602,y:1591) else { fatalError("No complete Minoc–Britain route found within search budget") }
    precondition(route.last?.x == 1602 && route.last?.y == 1591)
    var previous=start, bridgeSteps=0
    var local:NavigationMap?,center=start
    for point in route {
        let direction=WalkPath.direction(from:previous,to:point)!
        if local == nil || max(abs(previous.x-center.x),abs(previous.y-center.y))>24 {
            center=previous; local=try NavigationMap(assets:assets,center:previous,additional:[],radius:32)
        }
        precondition(local!.step(from:previous,direction:direction) == point,"Every global step must pass independent local collision checks")
        if let land=try assets.region(x:point.x,y:point.y,radius:0).first(where:{ !$0.isStatic }),
           try assets.landFlags(graphic:land.art)&0xC0 != 0 { bridgeSteps+=1 }
        previous=point
    }
    print("Every step verified against independent local collision snapshots; \(bridgeSteps) cross blocked base terrain")
    print("Complete Minoc–Britain static route: \(route.count) steps in \(Int(Date().timeIntervalSince(began))) seconds")
 }
}
