import Foundation

/// Provenance for confirmed automatic pickups, never a claim on the whole bag.
/// Credits are quantities within specific stacks; pre-existing quantities remain
/// protected when the server merges a pickup into an existing stack.
public struct GatheredInventory {
    public struct Credit: Equatable, Sendable {
        public let serial: UInt32
        public let graphic: Int
        public let hue: Int
        public let container: UInt32
        public fileprivate(set) var amount: Int
        fileprivate var observedAmount: Int
    }
    public private(set) var credits: [UInt32:Credit] = [:]
    public init() {}

    public mutating func reconcile(_ contents:[ContainerItem]) {
        let items=Dictionary(contents.map { ($0.serial,$0) },uniquingKeysWith:{ _,last in last })
        for (serial,var credit) in credits {
            guard let item=items[serial],item.container==credit.container,
                  item.graphic==credit.graphic,item.hue==credit.hue else {
                credits.removeValue(forKey:serial); continue
            }
            // Treat consumption or any untracked reduction as using gathered
            // goods first. Unrelated additions never earn automation credit.
            credit.amount=max(0,credit.amount-max(0,credit.observedAmount-item.amount))
            credit.observedAmount=item.amount
            if credit.amount==0 { credits.removeValue(forKey:serial) }
            else { credits[serial]=credit }
        }
    }

    public mutating func confirm(graphic:Int,hue:Int,amount:Int,bag:UInt32,
                                 before:[ContainerItem],after:[ContainerItem]) {
        reconcile(after)
        let previous=Dictionary(before.map { ($0.serial,$0) },uniquingKeysWith:{ _,last in last })
        var remaining=max(0,amount)
        for item in after.sorted(by:{ $0.serial<$1.serial }) where item.container==bag && item.graphic==graphic && item.hue==hue {
            let old=previous[item.serial]
            let oldAmount=old?.container==bag && old?.graphic==graphic && old?.hue==hue ? old!.amount : 0
            let gained=min(remaining,max(0,item.amount-oldAmount))
            guard gained>0 else { continue }
            let prior=credits[item.serial]?.amount ?? 0
            credits[item.serial]=Credit(serial:item.serial,graphic:graphic,hue:hue,container:bag,
                                        amount:min(item.amount,prior+gained),observedAmount:item.amount)
            remaining-=gained
            if remaining==0 { break }
        }
    }

    /// Manual use/drag/equip takes the item out of automation's control.
    public mutating func relinquish(_ serial:UInt32) { credits.removeValue(forKey:serial) }

    public func transferable(in bag:UInt32,includeGold:Bool)->[Credit] {
        credits.values.filter { $0.container==bag && $0.amount>0 && (includeGold || !(0xEED...0xEEF).contains($0.graphic)) }
            .sorted { $0.serial<$1.serial }
    }
}
