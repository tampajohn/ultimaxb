import Foundation

/// Classic-era result profile derived from the local mining/bladed scripts.
/// Construct only after sending the active attempt's target, and discard on
/// manual action/disconnect. The protocol has no harvest transaction ID.
public struct HarvestOutcome {
    public enum Kind { case mining, lumberjacking }
    private enum Destination { case backpack, feet }
    private let kind:Kind
    private let backpack:UInt32
    private let feet:WalkPoint
    private let started:TimeInterval
    private let beforeBag:Int, beforeGround:Int
    private var destination:Destination?
    private var finished=false
    public init(kind:Kind,backpack:UInt32,position:WalkPoint,world:WorldState,time:TimeInterval) {
        self.kind=kind; self.backpack=backpack; feet=position; started=time
        beforeBag=Self.bagAmount(kind,backpack,world)
        beforeGround=Self.groundAmount(kind,position,world)
    }
    private static func matches(_ kind:Kind,_ graphic:Int)->Bool {
        switch kind {
        case .mining: return (0x19B7...0x19BA).contains(graphic)
        case .lumberjacking: return graphic==0x1BDD
        }
    }
    private static func bagAmount(_ kind:Kind,_ bag:UInt32,_ world:WorldState)->Int {
        world.containerItems.values.filter { $0.container==bag && matches(kind,$0.graphic) }.reduce(0) { $0+max(1,$1.amount) }
    }
    private static func groundAmount(_ kind:Kind,_ feet:WalkPoint,_ world:WorldState)->Int {
        world.items.values.filter { $0.x==feet.x && $0.y==feet.y && $0.z==feet.z && matches(kind,$0.graphic) }.reduce(0) { $0+max(1,$1.amount) }
    }
    /// No message strings are retained or logged. Updates and system text may
    /// arrive in either order; neither alone proves a successful resource gain.
    public mutating func observe(speech:SpeechMessage?=nil,world:WorldState,time:TimeInterval)->AssistantAction.Result? {
        guard !finished else { return nil }
        guard time.isFinite,started.isFinite,time>=started,time-started<10 else { finished=true; return nil }
        if let speech,speech.serial == .max,speech.type==6 {
            let text=speech.text
            let empty:String, depleted:Set<String>, bag:String, ground:String
            switch kind {
            case .mining:
                empty="You loosen some rocks but fail to find any useable ore."
                depleted=["There is no metal here to mine.","Someone has gotten to the metal before you."]
                bag="You dig some ore and put it in your backpack."
                ground="You dig some ore and put it at your feet."
            case .lumberjacking:
                empty="You hack at the tree for a while, but fail to produce any useable wood."
                depleted=["There's not enough wood here to harvest."]
                bag="You put some logs in your backpack."
                ground="You put some logs at your feet."
            }
            if text==empty { return finish(.noYield) }
            if depleted.contains(text) { return finish(.depleted) }
            let refused:Set<String>=["That is too far away.","You can't see that.","You can't mine there.","You can't mine that.","You can't mine while riding.","You can't mine while polymorphed.","You have moved too far away to continue mining.","The axe must me equipped for any serious wood chopping.","You can't use an axe on that.","That wood belongs to someone else."]
            if refused.contains(text) { return finish(.refused) }
            if text==bag { destination = .backpack }
            if text==ground { destination = .feet }
        }
        switch destination {
        case .backpack where Self.bagAmount(kind,backpack,world)>beforeBag: return finish(.success)
        case .feet where Self.groundAmount(kind,feet,world)>beforeGround: return finish(.success)
        default: return nil
        }
    }
    private mutating func finish(_ result:AssistantAction.Result)->AssistantAction.Result { finished=true; return result }
}
