import Foundation

/// Resource-art rules from the chosen classic era's itemmanip script. These
/// identify possible targets, not whether the server's resource bank is depleted.
public enum HarvestSitePlanner {
    public struct Plan {
        public let sites:[HarvestWorkflow.Site]
        public let reachablePoints:Int
        public let searchTruncated:Bool
        public let omittedSites:Int
    }
    public static func accepts(kind:HarvestOutcome.Kind,graphic:Int,isStatic:Bool)->Bool {
        let ranges:[ClosedRange<Int>]
        switch kind {
        case .lumberjacking:
            guard isStatic else { return false }
            ranges=[0xC95...0xC96,0xC9E...0xC9E,0xCCA...0xCE6,0xCE8...0xCE8,0xCF8...0xD03,
                    0xD41...0xD53,0xD6E...0xD7F,0xD84...0xD90,0xD94...0xD9A,0xD9C...0xDAB,
                    0x12B6...0x12BE,0x12C0...0x12C7,0x1323...0x1323]
        case .mining:
            if isStatic {
                ranges=[0x25C...0x276,0x27D...0x280,0x53B...0x54F,0x551...0x553,0x56A...0x56A,0x16E4...0x16F3]
            } else {
                ranges=[0xDC...0xE7,0xEC...0xF7,0xFC...0x107,0x10C...0x117,0x11E...0x129,
                        0x141...0x144,0x1D3...0x1DA,0x21F...0x243,0x245...0x26D,0x6CD...0x6DD,
                        0x6EB...0x6FE,0x709...0x720,0x727...0x73E,0x745...0x75C,0x7BD...0x7D4]
            }
        }
        return ranges.contains { $0.contains(graphic) }
    }
    /// The live adapter and installed-map regression share this route builder.
    /// Asset regions allow at most radius 64, sufficient for a 65-tile work zone.
    public static func route(assets:ClientAssets,zone:HarvestWorkflow.Zone,from start:WalkPoint,to goal:WalkPoint,
                             additional:[WorldTile]=[])->[WalkPoint]? {
        guard zone.contains(x:start.x,y:start.y),zone.contains(x:goal.x,y:goal.y),
              let map=try? NavigationMap(assets:assets,center:start,additional:additional,radius:64) else { return nil }
        return WalkPath.find(from:start,x:goal.x,y:goal.y,goalZ:goal.z,limit:8192) { point,direction in
            guard let next=map.step(from:point,direction:direction),zone.contains(x:next.x,y:next.y) else { return nil }
            return next
        }
    }
    /// Installed-map adapter: live blocking items participate in collision but
    /// are not harvested merely because their art resembles a tree or rock.
    public static func discover(assets:ClientAssets,zone:HarvestWorkflow.Zone,kind:HarvestOutcome.Kind,
                                start:WalkPoint,additional:[WorldTile]=[]) throws -> Plan {
        let center=WalkPoint(x:(zone.minX+zone.maxX)/2,y:(zone.minY+zone.maxY)/2,z:start.z)
        let radius=max(zone.maxX-center.x,zone.maxY-center.y)
        let tiles=try assets.region(x:center.x,y:center.y,radius:radius)
        let navigation=try NavigationMap(assets:assets,center:center,additional:additional,radius:radius)
        return discover(zone:zone,kind:kind,start:start,tiles:tiles) { navigation.step(from:$0,direction:$1) }
    }
    /// Flood only the connected walkable area inside the zone. One flood avoids
    /// an expensive independent A* search for every resource graphic.
    public static func discover(zone:HarvestWorkflow.Zone,kind:HarvestOutcome.Kind,start:WalkPoint,
                                tiles:[WorldTile],limit:Int=32768,step:(WalkPoint,UInt8)->WalkPoint?)->Plan {
        guard zone.contains(x:start.x,y:start.y),(-128...127).contains(start.z),limit>0 else {
            return Plan(sites:[],reachablePoints:0,searchTruncated:false,omittedSites:0)
        }
        let budget=min(32768,limit)
        var queue=[start],seen:Set<WalkPoint>=[start],head=0
        var truncated=false
        // First BFS arrival supplies the nearest reachable standing point for
        // each target XY. The target itself retains its actual terrain/static Z.
        struct XY:Hashable { let x:Int,y:Int }
        var standing:[XY:(WalkPoint,Int)]=[:]
        var distance:[WalkPoint:Int]=[start:0]
        while head<queue.count && head<budget {
            let current=queue[head]; head += 1
            for dx in -1...1 { for dy in -1...1 {
                let key=XY(x:current.x+dx,y:current.y+dy)
                if standing[key]==nil { standing[key]=(current,distance[current]!) }
            } }
            for direction in UInt8(0)...7 {
                guard let next=step(current,direction),zone.contains(x:next.x,y:next.y),
                      (-128...127).contains(next.z),WalkPath.direction(from:current,to:next) != nil,
                      !seen.contains(next) else { continue }
                guard seen.count<budget else { truncated=true; continue }
                seen.insert(next); distance[next]=distance[current]!+1; queue.append(next)
            }
        }
        struct Key:Hashable { let x:Int,y:Int,z:Int,graphic:Int }
        var targets:Set<Key>=[]
        var candidates:[(HarvestWorkflow.Site,Int)]=[]
        for tile in tiles where !tile.isDynamic && zone.contains(x:tile.x,y:tile.y) && (-128...127).contains(tile.z) {
            let graphic=tile.isStatic ? tile.art-0x4000 : tile.art
            guard accepts(kind:kind,graphic:graphic,isStatic:tile.isStatic),
                  let (point,steps)=standing[XY(x:tile.x,y:tile.y)] else { continue }
            let targetGraphic=tile.isStatic ? graphic : 0
            let key=Key(x:tile.x,y:tile.y,z:tile.z,graphic:targetGraphic)
            guard targets.insert(key).inserted else { continue }
            candidates.append((.init(target:.init(x:tile.x,y:tile.y,z:tile.z,graphic:targetGraphic),standing:point),steps))
        }
        candidates.sort {
            let a=$0.0.target,b=$1.0.target
            return ($0.1,a.x,a.y,a.z,a.graphic)<($1.1,b.x,b.y,b.z,b.graphic)
        }
        return Plan(sites:candidates.prefix(256).map(\.0),reachablePoints:queue.count,
                    searchTruncated:truncated,omittedSites:max(0,candidates.count-256))
    }
}
