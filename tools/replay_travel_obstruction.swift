import Foundation
@testable import UOCore

/// Replay a local travel_section_blocked JSON row against installed assets.
/// No network connection, account access or character movement. Inputs stay in build/.
@main struct ReplayTravelObstruction {
    struct Snapshot:Decodable {
        let x:Int,y:Int,z:Int
        let ghost:Bool
        let goals:[[Int]],blocked:[[Int]],door_leaves:[[Int]],collision_tiles:[[Int]]
        let tile_count:Int
    }
    enum InputError:Error { case usage, invalidCoordinates, truncatedTiles }
    static func main() throws {
        guard CommandLine.arguments.count==3 else {
            print("Usage: replay_travel_obstruction <client-directory> <snapshot.json>")
            throw InputError.usage
        }
        let snapshot=try JSONDecoder().decode(Snapshot.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
        guard snapshot.tile_count==snapshot.collision_tiles.count else { throw InputError.truncatedTiles }
        func point(_ values:[Int]) throws ->WalkPoint {
            guard values.count==3 else { throw InputError.invalidCoordinates }
            return WalkPoint(x:values[0],y:values[1],z:values[2])
        }
        let assets=try ClientAssets(directory:URL(fileURLWithPath:CommandLine.arguments[1]))
        let start=WalkPoint(x:snapshot.x,y:snapshot.y,z:snapshot.z)
        let tiles=try snapshot.collision_tiles.map { values -> WorldTile in
            guard values.count==5,values[3]>=0x4000 else { throw InputError.invalidCoordinates }
            var tile=WorldTile(x:values[0],y:values[1],z:values[2],art:values[3],hue:0)
            tile.isDynamic=values[4] != 0
            return tile
        }
        let map=try NavigationMap(assets:assets,center:start,additional:tiles,radius:48,ghost:snapshot.ghost)
        let leaves=Set(try snapshot.door_leaves.map(point)),blocked=Set(try snapshot.blocked.map(point))
        let goals=try snapshot.goals.map(point)
        print("Start: \(start); \(tiles.count) live collision tiles; \(leaves.count) opened leaves")
        for (index,goal) in goals.enumerated() {
            for (name,ignoreDoors,retainLeaves) in [("ordinary",false,true),("closed doors relaxed",true,true),("without remembered-leaf exclusions (diagnostic only)",true,false)] {
                var statistics:WalkPath.SearchStatistics?
                let route=WalkPath.find(from:start,x:goal.x,y:goal.y,goalZ:goal.z,limit:8192,travelCost:map.travelCost,report:{statistics=$0}) { p,d in
                    guard let next=map.step(from:p,direction:d,ignoringDoors:ignoreDoors),!blocked.contains(next),
                          !retainLeaves || TravelSafety.clearsDoorLeaves(from:p,to:next,leaves:leaves) else { return nil }
                    return next
                }
                print("Goal \(index) \(goal), \(name): \(route.map { "\($0.count) steps" } ?? "no route"), \(statistics!.outcome.rawValue), expanded \(statistics!.expanded)")
            }
        }
        for tile in tiles where max(abs(tile.x-start.x),abs(tile.y-start.y))<=4 {
            let graphic=tile.art-0x4000
            print(String(format:"Nearby tile 0x%04X at %d,%d,%d height=%d flags=0x%X",graphic,tile.x,tile.y,tile.z,try assets.itemHeight(graphic:graphic),try assets.itemFlags(graphic:graphic)))
        }
    }
}
