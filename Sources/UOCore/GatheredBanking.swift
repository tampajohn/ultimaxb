import Foundation

/// Server-driven banking workflow. The caller sends each returned command once,
/// then feeds authoritative inventory/open/contents events before polling again.
public struct GatheredBanking {
    public enum Command:Equatable { case openBank, deposit(serial:UInt32,amount:Int,bank:UInt32) }
    public enum State:Equatable { case idle, opening, waitingContents, ready, transferring, retrying, complete, stopped(String) }
    public private(set) var state:State = .idle
    public private(set) var bank:UInt32?
    public private(set) var depositedAmount=0
    public private(set) var confirmedTransfers=0
    private var player:UInt32=0
    private var point=WalkPoint(x:0,y:0,z:0)
    private var deadline:TimeInterval=0
    private var transfer:Transfer?
    private var nextDepositAt:TimeInterval=0
    public private(set) var retryCount=0
    private struct Transfer {
        let source:UInt32, sourceBag:UInt32, graphic:Int, hue:Int, amount:Int
        let beforeSource:Int, beforeDestination:Int
        let destinationContainer:UInt32, target:UInt32
    }
    public init() {}
    public mutating func begin(player:UInt32,at point:WalkPoint,time:TimeInterval)->Command {
        self.player=player; self.point=point; bank=nil; transfer=nil; retryCount=0; nextDepositAt=time
        depositedAmount=0; confirmedTransfers=0
        state = .opening; deadline=time+5
        return .openBank
    }
    public mutating func opened(_ serial:UInt32,equipment:[EquippedItem],time:TimeInterval) {
        guard state == .opening,
              equipment.contains(where:{$0.serial==serial && $0.owner==player && $0.layer==29}) else { return }
        bank=serial; state = .waitingContents; deadline=time+5
    }
    /// Only a full contents response for the bank establishes the baseline;
    /// an empty bank still requires its explicit empty contents response.
    public mutating func contentsReceived(for serial:UInt32,time:TimeInterval=0) {
        guard state == .waitingContents,serial==bank else { return }
        state = .ready; nextDepositAt=time+1
    }
    public mutating func refuse(reason:UInt8?=nil,time:TimeInterval=0) {
        guard state == .transferring else { return }
        // 0x27/255 is the classic server's busy/unavailable lift rejection.
        // It is explicit rejection, unlike a timeout with an unknown outcome.
        if reason == 255,retryCount<3 {
            retryCount += 1; state = .retrying; deadline=time+Double(retryCount+1)
        } else { stop("Bank deposit refused by server.") }
    }
    public mutating func stop(_ reason:String) { state = .stopped(reason); transfer=nil }
    public mutating func next(position:WalkPoint,backpack:UInt32,equipment:[EquippedItem],
                              contents:[ContainerItem],gathered:GatheredInventory,time:TimeInterval,
                              stackable:(Int)->Bool = { _ in false })->Command? {
        switch state { case .idle,.complete,.stopped: return nil; default: break }
        guard position==point else { stop("Banking stopped because the player moved."); return nil }
        if state == .opening || state == .waitingContents {
            if time>=deadline { stop("Bank did not open with confirmed contents.") }
            return nil
        }
        guard let bank,bank != backpack,
              equipment.contains(where:{$0.serial==bank && $0.owner==player && $0.layer==29}) else {
            stop("Player bank identity is no longer confirmed."); return nil
        }
        if let transfer {
            var ancestor=transfer.destinationContainer,seen=Set<UInt32>()
            while ancestor != bank {
                guard seen.insert(ancestor).inserted,
                      let parent=contents.first(where:{$0.serial==ancestor}) else {
                    stop("Bank destination is no longer available."); return nil
                }
                ancestor=parent.container
            }
            let source=contents.first(where:{$0.serial==transfer.source && $0.container==transfer.sourceBag && $0.graphic==transfer.graphic && $0.hue==transfer.hue})?.amount ?? 0
            let destination=contents.filter { $0.container==transfer.destinationContainer && $0.graphic==transfer.graphic && $0.hue==transfer.hue }.reduce(0) { $0+$1.amount }
            guard source<=transfer.beforeSource-transfer.amount && destination>=transfer.beforeDestination+transfer.amount else {
                if state == .retrying {
                    guard time>=deadline else { return nil }
                    // Only replay a rejected lift if both authoritative snapshots
                    // are unchanged. Partial/missing updates must never be replayed.
                    guard source==transfer.beforeSource,destination==transfer.beforeDestination else {
                        stop("Bank retry stopped: inventory changed after refusal."); return nil
                    }
                    if transfer.target != bank {
                        guard contents.contains(where: {
                            $0.serial==transfer.target && $0.container==transfer.destinationContainer &&
                            $0.graphic==transfer.graphic && $0.hue==transfer.hue
                        }) else { stop("Bank stack is no longer available."); return nil }
                    }
                    state = .transferring; deadline=time+5
                    return .deposit(serial:transfer.source,amount:transfer.amount,bank:transfer.target)
                }
                if time>=deadline { stop("Bank deposit was not confirmed.") }
                return nil
            }
            depositedAmount += transfer.amount; confirmedTransfers += 1
            self.transfer=nil; state = .ready; retryCount=0; nextDepositAt=time+1
            // Wait for the caller to reconcile the gathered ledger. Never emit
            // the next transfer using the same pre-confirmation snapshot.
            return nil
        }
        guard time>=nextDepositAt else { return nil }
        var eligible=gathered
        eligible.reconcile(contents)
        guard let credit=eligible.transferable(in:backpack,includeGold:true).first else {
            state = .complete; return nil
        }
        guard let source=contents.first(where:{$0.serial==credit.serial && $0.container==backpack}) else { return nil }
        // Follow only known ancestry rooted at this player's bank. A cycle,
        // unknown parent or another owner's container never qualifies.
        let bySerial=Dictionary(contents.map { ($0.serial,$0) },uniquingKeysWith:{ first,_ in first })
        func depth(_ container:UInt32)->Int? {
            var current=container,seen=Set<UInt32>(),depth=0
            while current != bank {
                guard seen.insert(current).inserted,let parent=bySerial[current] else { return nil }
                current=parent.container; depth += 1
            }
            return depth
        }
        let matching=stackable(credit.graphic) ? contents.filter {
            $0.graphic==credit.graphic && $0.hue==credit.hue &&
            $0.amount>0 && $0.amount<=65535-credit.amount && depth($0.container) != nil
        }.sorted {
            let a=depth($0.container)!,b=depth($1.container)!
            return a == b ? $0.serial<$1.serial : a<b
        }.first : nil
        let destination=matching?.container ?? bank
        let target=matching?.serial ?? bank
        transfer=Transfer(source:source.serial,sourceBag:backpack,graphic:credit.graphic,hue:credit.hue,amount:credit.amount,
                          beforeSource:source.amount,beforeDestination:contents.filter { $0.container==destination && $0.graphic==credit.graphic && $0.hue==credit.hue }.reduce(0) { $0+$1.amount },destinationContainer:destination,target:target)
        deadline=time+5; state = .transferring
        return .deposit(serial:credit.serial,amount:credit.amount,bank:target)
    }
}
