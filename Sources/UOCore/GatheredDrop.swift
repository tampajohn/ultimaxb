import Foundation

/// A single overload transfer. A disappearing source alone is not success:
/// the corresponding quantity must also appear at the requested ground tile.
public struct GatheredDrop {
    public enum Result:Equatable { case waiting, confirmed, refused, timedOut }
    public let serial:UInt32, amount:Int, point:WalkPoint
    private let graphic:Int, hue:Int, bag:UInt32, beforeBag:Int, beforeGround:Int
    private let started:TimeInterval
    private var refused=false
    public init(credit:GatheredInventory.Credit,amount:Int,point:WalkPoint,
                contents:[ContainerItem],ground:[GroundItem],at:TimeInterval) {
        self.serial=credit.serial; self.amount=min(max(1,amount),credit.amount); self.point=point
        graphic=credit.graphic; hue=credit.hue; bag=credit.container; started=at
        beforeBag=contents.filter { $0.container==credit.container && $0.graphic==credit.graphic && $0.hue==credit.hue }.reduce(0) { $0+$1.amount }
        beforeGround=ground.filter { $0.x==point.x && $0.y==point.y && $0.z==point.z && $0.graphic==credit.graphic && $0.hue==credit.hue }.reduce(0) { $0+max(1,$1.amount) }
    }
    public mutating func receive(_ packet:Data) {
        if packet.first==0x27 || packet.first==0x28 { refused=true }
    }
    public func droppedItems(_ ground:[GroundItem])->[GroundItem] {
        ground.filter { $0.x==point.x && $0.y==point.y && $0.z==point.z && $0.graphic==graphic && $0.hue==hue }
    }
    public func result(contents:[ContainerItem],ground:[GroundItem],at:TimeInterval)->Result {
        if refused { return .refused }
        let inBag=contents.filter { $0.container==bag && $0.graphic==graphic && $0.hue==hue }.reduce(0) { $0+$1.amount }
        let onGround=droppedItems(ground).reduce(0) { $0+max(1,$1.amount) }
        if inBag<=beforeBag-amount && onGround>=beforeGround+amount { return .confirmed }
        return at-started>=5 ? .timedOut : .waiting
    }
}
