import Foundation
@testable import UOCore

@main struct Check {
    static func main() throws {
        let assets=try ClientAssets(directory:URL(fileURLWithPath:CommandLine.arguments.dropFirst().first ?? "uo1998-client"))
        for (name,kind,x,y) in [("Minoc mountains",HarvestOutcome.Kind.mining,2584,482),("Minoc woodland",.lumberjacking,2603,309)] {
            let z=try assets.elevation(x:x,y:y)
            let start=WalkPoint(x:x,y:y,z:z)
            let zone=try HarvestWorkflow.Zone(x1:x-16,y1:y-16,x2:x+16,y2:y+16)
            let navigation=try NavigationMap(assets:assets,center:start,additional:[],radius:17)
            guard let player=navigation.standingPoint(x:x,y:y,fromZ:z) else { fatalError("Fixture has no standing surface") }
            let plan=try HarvestSitePlanner.discover(assets:assets,zone:zone,kind:kind,start:player)
            precondition(!plan.sites.isEmpty,"Installed map should contain reachable work sites")
            precondition(!plan.searchTruncated)
            var checked=Set<WalkPoint>()
            for site in plan.sites {
                precondition(zone.contains(x:site.target.x,y:site.target.y))
                precondition(!ToolReach.needsApproach(playerX:site.standing.x,playerY:site.standing.y,target:site.target))
                let path=WalkPath.find(from:player,x:site.standing.x,y:site.standing.y,goalZ:site.standing.z,limit:8192) { point,direction in
                    guard let next=navigation.step(from:point,direction:direction),zone.contains(x:next.x,y:next.y) else { return nil }
                    return next
                }
                precondition(path != nil,"Every planned standing tile must be independently reachable")
                if checked.insert(site.standing).inserted {
                    let live=HarvestSitePlanner.route(assets:assets,zone:zone,from:player,to:site.standing)
                    precondition(live != nil && (live!.isEmpty ? player : live!.last!) == site.standing,
                                 "The exact live route builder must reach each standing surface")
                }
            }
            print("\(name): \(plan.sites.count) reachable sites, \(plan.reachablePoints) standing points, \(plan.omittedSites) sites beyond display limit")
        }
    }
}
