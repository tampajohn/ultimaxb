import Foundation
import UOCore

/// Installed-map regression only; never connects or moves the live character.
@main struct Check {
    static func main() throws {
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let minoc=WalkPoint(x:2502,y:547,z:0)
        let skara=WalkPoint(x:618,y:2234,z:try assets.elevation(x:618,y:2234))
        for (name,start,x,y,adjacent,connected) in [
            ("Minoc–Britain bank",minoc,1427,1685,true,true),
            ("Minoc–Skara bank",minoc,591,2142,true,false),
            ("Minoc–Skara inn",minoc,618,2234,false,false),
            ("Skara inn–bank",skara,591,2142,true,true)
        ] {
            let planner=WorldTravelPlanner(assets:assets),began=Date()
            let route=try planner.find(from:start,x:x,y:y,adjacent:adjacent)
            if connected {
                guard let route,let end=route.last else { fatalError("Expected connected route: \(name)") }
                precondition(max(abs(end.x-x),abs(end.y-y)) <= (adjacent ? 1 : 0))
                var previous=start,center=start,local:NavigationMap?
                for next in route {
                    if local == nil || max(abs(previous.x-center.x),abs(previous.y-center.y))>24 {
                        center=previous
                        local=try NavigationMap(assets:assets,center:previous,additional:[],radius:32)
                    }
                    guard let direction=WalkPath.direction(from:previous,to:next),
                          local?.step(from:previous,direction:direction)==next else {
                        fatalError("Invalid forward edge: \(previous) -> \(next)")
                    }
                    previous=next
                }
            } else {
                precondition(route == nil)
                precondition(planner.attempts.last?.strategy=="destination_connectivity")
                precondition(planner.attempts.last?.statistics.outcome == .exhausted,
                             "An exhausted budget is not proof of disconnection")
            }
            let counts=planner.attempts.map { "\($0.strategy):\($0.statistics.outcome.rawValue)/\($0.statistics.expanded)" }.joined(separator:", ")
            print("\(name): \(route?.count ?? 0) forward-validated steps; \(counts); \(String(format:"%.2f",Date().timeIntervalSince(began)))s")
        }
    }
}
