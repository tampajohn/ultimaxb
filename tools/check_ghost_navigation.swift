import Foundation
@testable import UOCore

@main struct CheckGhostNavigation {
    static func main() throws {
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let center = WalkPoint(x:2603,y:309,z:15)
        let base = try NavigationMap(assets:assets,center:center,additional:[])
        let door = try (0..<0x1000).first {
            try assets.itemFlags(graphic:$0) & 0x20000040 == 0x20000040 && assets.itemHeight(graphic:$0) >= 16
        }!
        var checked = false
        for direction in UInt8(0)...7 {
            guard let destination = base.step(from:center,direction:direction) else { continue }
            var tile = WorldTile(x:destination.x,y:destination.y,z:destination.z,art:door+0x4000,hue:0)
            tile.isDynamic = true
            let living = try NavigationMap(assets:assets,center:center,additional:[tile])
            let ghost = try NavigationMap(assets:assets,center:center,additional:[tile],ghost:true)
            precondition(living.step(from:center,direction:direction) == nil)
            precondition(ghost.step(from:center,direction:direction) == destination)
            precondition(ghost.standingPoint(x:destination.x,y:destination.y,fromZ:center.z) == destination)
            let route = WalkPath.find(from:center,x:destination.x,y:destination.y) { ghost.step(from:$0,direction:$1) }
            precondition(route == [destination])
            checked = true
            break
        }
        precondition(checked, "Fixture needs one open adjacent terrain cell")
        let unknownWeight = try assets.itemWeight(graphic:0xFFFF)
        precondition(unknownWeight == 255)
        print("Installed terrain/tiledata: living collision blocks closed door; ghost routing and destination preserve terrain elevation")
    }
}
