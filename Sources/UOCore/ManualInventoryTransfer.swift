import Foundation

/// Serializes manual lift/drop pairs without predicting ownership or replaying them.
public struct ManualInventoryTransfer {
    public enum Destination { case container(UInt32, x:Int, y:Int), ground(Int,Int,Int), equipment(UInt32,UInt8) }
    public enum Result:String { case placed, refused, timedOut }
    public private(set) var serial:UInt32?
    private var destination:Destination = .ground(0,0,0)
    private var amount=0, graphic=0, hue=0
    private var deadline:TimeInterval=0
    private var before:[UInt32:Int]=[:]
    private var wholeStack=false
    private var sourceContainer:ContainerItem?
    private var sourceGround:GroundItem?
    public init() {}
    public mutating func begin(serial:UInt32,amount:Int,destination:Destination,world:WorldState,time:TimeInterval) {
        self.serial=serial; self.amount=amount; self.destination=destination; deadline=time+5
        graphic=world.containerItems[serial]?.graphic ?? world.items[serial]?.graphic ?? world.equipment[serial]?.graphic ?? -1
        hue=world.containerItems[serial]?.hue ?? world.items[serial]?.hue ?? world.equipment[serial]?.hue ?? -1
        wholeStack=amount >= (world.containerItems[serial]?.amount ?? world.items[serial]?.amount ?? 1)
        before=matching(world)
        sourceContainer=world.containerItems[serial]; sourceGround=world.items[serial]
    }
    private func matching(_ world:WorldState)->[UInt32:Int] {
        switch destination {
        case .container(let bag,_,_):
            var result=Dictionary(uniqueKeysWithValues:world.containerItems.values.filter { ($0.container==bag || $0.serial==bag) && $0.graphic==graphic && $0.hue==hue }.map { ($0.serial,$0.amount) })
            if let stack=world.items[bag],stack.graphic==graphic,stack.hue==hue { result[bag]=stack.amount }
            return result
        case .ground(let x,let y,let z):
            return Dictionary(uniqueKeysWithValues:world.items.values.filter { $0.x==x && $0.y==y && $0.z==z && $0.graphic==graphic && $0.hue==hue }.map { ($0.serial,$0.amount) })
        case .equipment: return [:]
        }
    }
    public mutating func receive(_ packet:Data,world:WorldState)->Result? {
        guard let serial else { return nil }
        if packet.first==0x27 || packet.first==0x28 { return finish(.refused) }
        var touched:Set<UInt32>=[]
        switch packet.first {
        case 0x25,0x3C: touched=Set((try? ContainerItem.decode(packet))?.map(\.serial) ?? [])
        case 0x1A: if let item=try? GroundItem.decode(packet) { touched.insert(item.serial) }
        case 0x2E: if let item=try? EquippedItem.decode(packet) { touched.insert(item.serial) }
        default: return nil
        }
        if touched.contains(serial) {
            switch destination {
            case .equipment(let owner,let layer):
                if let item=world.equipment[serial],item.owner==owner,item.layer==layer { return finish(.placed) }
            case .container(let bag,let x,let y):
                if let item=world.containerItems[serial],item.container==bag,
                   (x==0xFFFF || item.x==x),(y==0xFFFF || item.y==y),
                   wholeStack || before[serial]==nil || sourceContainer.map({ $0.x != item.x || $0.y != item.y }) == true { return finish(.placed) }
            case .ground(let x,let y,let z):
                if let item=world.items[serial],item.x==x,item.y==y,item.z==z,
                   wholeStack || before[serial]==nil || sourceGround.map({ $0.x != item.x || $0.y != item.y || $0.z != item.z }) == true { return finish(.placed) }
            }
        }
        // Splitting or stacking may create/update a different serial. Count only
        // positive changes delivered in this placement packet, excluding the
        // source remainder; its reduction alone is never a completed drop.
        let after=matching(world)
        let received=touched.filter { $0 != serial }.reduce(0) { $0+max(0,(after[$1] ?? 0)-(before[$1] ?? 0)) }
        if received>=amount { return finish(.placed) }
        return nil
    }
    public mutating func poll(time:TimeInterval)->Result? {
        guard serial != nil,time>=deadline else { return nil }
        return finish(.timedOut)
    }
    private mutating func finish(_ result:Result)->Result { serial=nil; before=[:]; return result }
}
