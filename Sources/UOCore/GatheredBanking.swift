import Foundation

/// Server-driven banking workflow. The caller sends each returned command once,
/// then feeds authoritative inventory/open/contents events before polling again.
public struct GatheredBanking {
    public enum Command:Equatable { case openBank, deposit(serial:UInt32,amount:Int,bank:UInt32) }
    public enum State:Equatable { case idle, opening, waitingContents, ready, transferring, complete, stopped(String) }
    public private(set) var state:State = .idle
    public private(set) var bank:UInt32?
    private var player:UInt32=0
    private var point=WalkPoint(x:0,y:0,z:0)
    private var deadline:TimeInterval=0
    private var transfer:Transfer?
    private struct Transfer {
        let source:UInt32, sourceBag:UInt32, graphic:Int, hue:Int, amount:Int
        let beforeSource:Int, beforeDestination:Int
    }
    public init() {}
    public mutating func begin(player:UInt32,at point:WalkPoint,time:TimeInterval)->Command {
        self.player=player; self.point=point; bank=nil; transfer=nil
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
    public mutating func contentsReceived(for serial:UInt32) {
        guard state == .waitingContents,serial==bank else { return }
        state = .ready
    }
    public mutating func refuse() {
        guard state == .transferring else { return }
        stop("Bank deposit refused by server.")
    }
    public mutating func stop(_ reason:String) { state = .stopped(reason); transfer=nil }
    public mutating func next(position:WalkPoint,backpack:UInt32,equipment:[EquippedItem],
                              contents:[ContainerItem],gathered:GatheredInventory,time:TimeInterval)->Command? {
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
            let source=contents.first(where:{$0.serial==transfer.source && $0.container==transfer.sourceBag && $0.graphic==transfer.graphic && $0.hue==transfer.hue})?.amount ?? 0
            let destination=contents.filter { $0.container==bank && $0.graphic==transfer.graphic && $0.hue==transfer.hue }.reduce(0) { $0+$1.amount }
            guard source<=transfer.beforeSource-transfer.amount && destination>=transfer.beforeDestination+transfer.amount else {
                if time>=deadline { stop("Bank deposit was not confirmed.") }
                return nil
            }
            self.transfer=nil; state = .ready
            // Wait for the caller to reconcile the gathered ledger. Never emit
            // the next transfer using the same pre-confirmation snapshot.
            return nil
        }
        var eligible=gathered
        eligible.reconcile(contents)
        guard let credit=eligible.transferable(in:backpack,includeGold:true).first else {
            state = .complete; return nil
        }
        guard let source=contents.first(where:{$0.serial==credit.serial && $0.container==backpack}) else { return nil }
        transfer=Transfer(source:source.serial,sourceBag:backpack,graphic:credit.graphic,hue:credit.hue,amount:credit.amount,
                          beforeSource:source.amount,beforeDestination:contents.filter { $0.container==bank && $0.graphic==credit.graphic && $0.hue==credit.hue }.reduce(0) { $0+$1.amount })
        deadline=time+5; state = .transferring
        return .deposit(serial:credit.serial,amount:credit.amount,bank:bank)
    }
}
