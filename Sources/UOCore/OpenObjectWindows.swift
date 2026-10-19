import Foundation

/// Open UI objects have a lifetime independent of whether their contents are empty.
public struct OpenObjectWindows {
    private struct Access {
        var ancestors:Set<UInt32>
        var anchor:WalkPoint?
    }
    private var open:[UInt32:Access]=[:]
    public init() {}
    public mutating func register(_ serial:UInt32,world:WorldState,player:UInt32?) {
        guard open.count<64 || open[serial] != nil else { return }
        open[serial]=access(serial,world:world,player:player,previous:nil)
    }
    public mutating func dismiss(_ serial:UInt32) { open.removeValue(forKey:serial) }
    public mutating func removed(_ serial:UInt32)->Set<UInt32> {
        let closed=Set(open.filter { $0.key == serial || $0.value.ancestors.contains(serial) }.keys)
        for id in closed { open.removeValue(forKey:id) }
        return closed
    }
    public mutating func reconcile(world:WorldState,player:UInt32?)->Set<UInt32> {
        guard let player,let mobile=world.mobiles[player] else { return [] }
        var closed=Set<UInt32>()
        for (serial,previous) in open {
            let current=access(serial,world:world,player:player,previous:previous)
            if let anchor=current.anchor,
               max(abs(anchor.x-mobile.x),abs(anchor.y-mobile.y))>3 || abs(anchor.z-mobile.z)>20 {
                closed.insert(serial)
            } else { open[serial]=current }
        }
        for serial in closed { open.removeValue(forKey:serial) }
        return closed
    }
    private func access(_ serial:UInt32,world:WorldState,player:UInt32?,previous:Access?)->Access {
        var parents:Set<UInt32>=[],node=serial
        while parents.insert(node).inserted {
            if let item=world.containerItems[node] { node=item.container; continue }
            if let equipped=world.equipment[node] {
                if equipped.owner == player && equipped.layer != 29 {
                    parents.insert(equipped.owner); return Access(ancestors:parents,anchor:nil)
                }
                if equipped.layer == 29,let owner=world.mobiles[equipped.owner] {
                    parents.insert(equipped.owner)
                    return Access(ancestors:parents,anchor:previous?.anchor ?? WalkPoint(x:owner.x,y:owner.y,z:owner.z))
                }
                node=equipped.owner; continue
            }
            if let item=world.items[node] { return Access(ancestors:parents,anchor:WalkPoint(x:item.x,y:item.y,z:item.z)) }
            if let owner=world.mobiles[node] { return Access(ancestors:parents,anchor:WalkPoint(x:owner.x,y:owner.y,z:owner.z)) }
            // Some servers open bank roots without first sending an item record.
            // Retain the last proven relationship; absence alone is not deletion.
            return Access(ancestors:parents.union(previous?.ancestors ?? []),anchor:previous?.anchor)
        }
        return Access(ancestors:parents,anchor:previous?.anchor)
    }
}
