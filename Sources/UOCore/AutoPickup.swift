import Foundation

/// One server-confirmed lift/drop at a time. Never retries an observed serial.
public struct AutoPickup {
    public enum Mode:Int { case off, reagents, all }
    public var mode:Mode = .off
    public private(set) var pending:UInt32?
    public private(set) var stoppedReason:String?
    private var attempted:Set<UInt32> = []
    private var sentAt:TimeInterval = 0
    private var bag:UInt32=0, graphic=0, hue=0, previousAmount=0, pickedAmount=0
    private var nextAt:TimeInterval=0
    public init() {}
    public static let reagents:Set<Int> = [0xF7A,0xF7B,0xF84,0xF85,0xF86,0xF88,0xF8C,0xF8D]
    public mutating func select(items:[GroundItem],player:WorldMobile,at time:TimeInterval,portable:(GroundItem)->Bool = { _ in true })->GroundItem? {
        attempted.formIntersection(Set(items.map(\.serial)).union(pending.map { [$0] } ?? []))
        guard mode != .off,pending == nil,time>=nextAt,!player.isGhost,player.flags & 0x40 == 0 else { return nil }
        return items.filter {
            !attempted.contains($0.serial) && portable($0) && $0.graphic<0x4000 && $0.graphic != 0x2006 && $0.flags & 0x80 == 0 &&
            max(abs($0.x-player.x),abs($0.y-player.y))<=1 && abs($0.z-player.z)<=16 &&
            (Self.reagents.contains($0.graphic) || mode == .all)
        }.sorted { $0.serial<$1.serial }.first
    }
    public mutating func begin(_ item:GroundItem,bag:UInt32,contents:[ContainerItem],at time:TimeInterval) {
        pending=item.serial; attempted.insert(item.serial); sentAt=time; stoppedReason=nil
        self.bag=bag; graphic=item.graphic; hue=item.hue; pickedAmount=max(1,item.amount)
        previousAmount=contents.filter { $0.container==bag && $0.graphic==item.graphic && $0.hue==item.hue }.reduce(0) { $0+max(1,$1.amount) }
    }
    public mutating func receive(_ packet:Data) {
        guard pending != nil else { return }
        if packet.first == 0x27 || packet.first == 0x28 {
            pending=nil; nextAt=sentAt+2
            stoppedReason="Auto-pickup skipped an item the server refused."
        }
    }
    public mutating func update(contents:[ContainerItem],at time:TimeInterval) {
        guard let pending else { return }
        let arrived=contents.contains { $0.serial==pending && $0.container==bag }
        let amount=contents.filter { $0.container==bag && $0.graphic==graphic && $0.hue==hue }.reduce(0) { $0+max(1,$1.amount) }
        if arrived || amount>=previousAmount+pickedAmount { self.pending=nil; nextAt=time+0.5 }
        else if time-sentAt>=5 { stop("Auto-pickup stopped: no confirmed inventory update.") }
    }
    public mutating func skip(_ serial:UInt32) { attempted.insert(serial) }
    public mutating func stop(_ reason:String) { mode = .off; pending=nil; stoppedReason=reason }
}
