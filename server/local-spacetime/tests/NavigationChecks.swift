import Foundation

@main
struct NavigationChecks {
    static func main() throws {
        typealias C = NavigationMap.Cell
        typealias S = NavigationMap.Surface
        precondition(C(landZ:4,lowZ:0,landBlocked:false,surfaces:[]).standingZ(from:0) == 4)
        precondition(C(landZ:9,lowZ:9,landBlocked:false,surfaces:[]).standingZ(from:0) == nil)
        precondition(C(landZ:-21,lowZ:-21,landBlocked:false,surfaces:[]).standingZ(from:0) == nil)
        precondition(C(landZ:0,lowZ:0,landBlocked:true,surfaces:[]).standingZ(from:0) == nil)
        let wall = S(z:0,height:20,flags:0x40)
        precondition(C(landZ:0,lowZ:0,landBlocked:false,surfaces:[wall]).standingZ(from:0) == nil)
        let bridge = S(z:0,height:10,flags:0x400)
        precondition(C(landZ:-20,lowZ:-20,landBlocked:true,surfaces:[bridge]).standingZ(from:0) == 5)
        let floor = S(z:0,height:4,flags:0x200), ceiling = S(z:18,height:1,flags:0x40)
        precondition(C(landZ:0,lowZ:0,landBlocked:true,surfaces:[floor,ceiling]).standingZ(from:0) == nil)
        let assets = try ClientAssets(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
        let center = WalkPoint(x:1435,y:1695,z:0)
        let map = try NavigationMap(assets:assets,center:center,additional:[],radius:40)
        var slopes=0, blockers=0, corners=0
        for y in 1660...1730 {
            for x in 1400...1470 {
                guard let from = map.standingPoint(x:x,y:y,fromZ:0) else { continue }
                for direction in UInt8(0)...7 {
                    let delta = WalkPath.directions[Int(direction)]
                    let step = map.step(from:from,direction:direction)
                    if let step, step.z != from.z { slopes += 1 }
                    if step == nil { blockers += 1 }
                    if delta.0 != 0 && delta.1 != 0,
                       map.standingPoint(x:x+delta.0,y:y+delta.1,fromZ:from.z) != nil,
                       (map.standingPoint(x:x+delta.0,y:y,fromZ:from.z) == nil ||
                        map.standingPoint(x:x,y:y+delta.1,fromZ:from.z) == nil) {
                        precondition(step == nil, "Diagonal must not cut a blocked corner")
                        corners += 1
                    }
                }
            }
        }
        precondition(slopes > 0 && blockers > 0 && corners > 0)
        print("PASS: slope, climb/drop, water, wall, bridge, headroom rules; Britain assets: \(slopes) elevation edges, \(blockers) blocked edges, \(corners) blocked corners")
    }
}
