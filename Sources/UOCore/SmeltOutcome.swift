import Foundation

/// Correlates one ore-use/forge-target attempt with classic system feedback and
/// inventory changes. Construct after targeting the forge; discard on manual
/// inventory changes/disconnect. No elapsed-time success or guessed retry.
public struct SmeltOutcome {
    public enum Result:Equatable { case success, lostMetal, insufficientOre, refused, unreachable }
    private let ore:ContainerItem
    private let backpack:UInt32
    private let started:TimeInterval
    private let beforeIngots:Int
    private let beforeMatchingIngots:Int
    private var inventoryConfirmed=false
    private var successMessage=false,lossMessage=false,finished=false
    private var observedIngots=0,sourcePresent=false
    public var diagnostics:[String:Int] {
        ["success_message":successMessage ? 1:0,"loss_message":lossMessage ? 1:0,
         "ingots_before":beforeIngots,"ingots_observed":observedIngots,"source_present":sourcePresent ? 1:0,"inventory_confirmed":inventoryConfirmed ? 1:0]
    }
    public static func isForge(_ graphic:Int)->Bool { graphic==0xFB1 || (0x197A...0x19A9).contains(graphic) }
    public init(ore:ContainerItem,backpack:UInt32,world:WorldState,time:TimeInterval) throws {
        guard (0x19B7...0x19BA).contains(ore.graphic),ore.container==backpack,
              ore.amount>0,ore.serial != 0,ore.serial != .max,backpack != 0,backpack != .max,time.isFinite else {
            throw AssetError("Smelting requires a known ore stack in your backpack")
        }
        self.ore=ore; self.backpack=backpack; started=time
        beforeIngots=Self.ingots(backpack,world)
        beforeMatchingIngots=Self.ingots(backpack,world,hue:ore.hue)
    }
    private static func ingots(_ bag:UInt32,_ world:WorldState,hue:Int? = nil)->Int {
        world.containerItems.values.filter { $0.container==bag && $0.graphic==0x1BF2 && (hue == nil || $0.hue==hue) }.reduce(0) { $0+max(1,$1.amount) }
    }
    public mutating func observe(speech:SpeechMessage?=nil,world:WorldState,time:TimeInterval)->Result? {
        guard !finished else { return nil }
        guard time.isFinite,time>=started,time-started<10 else { finished=true; return nil }
        observedIngots=Self.ingots(backpack,world); sourcePresent=world.containerItems[ore.serial] != nil
        if let speech,speech.serial == .max,speech.type==6 {
            switch speech.text {
            case "You smelt the ore removing the impurities and put the metal in your backpack.": successMessage=true
            case "You burn away the impurities but are left with no useable metal.",
                 "You burn away the impurities but are left with less useable metal.": lossMessage=true
            case "There is not enough metal-bearing ore in this pile to make an ingot.": return finish(.insufficientOre)
            case "That ore belongs to someone else.","Someone is using that ore.": return finish(.refused)
            case "That is too far away.","The ore is too far away.","You can't see that.": return finish(.unreachable)
            default: break
            }
        }
        if successMessage && Self.ingots(backpack,world)>beforeIngots { return finish(.success) }
        // Some live smelts deliver the complete inventory conversion without
        // repeating the system message. Require the exact expected same-metal
        // output AND consumption of this selected source, in either order.
        let metal=ore.amount*SmeltWorkflow.metalUnits(graphic:ore.graphic)
        let expected=metal/2
        let gained=Self.ingots(backpack,world,hue:ore.hue)-beforeMatchingIngots
        let consumed:Bool
        if let remainder=world.containerItems[ore.serial] {
            consumed=remainder.container==backpack && remainder.hue==ore.hue &&
                SmeltWorkflow.metalUnits(graphic:remainder.graphic)>0 &&
                remainder.amount*SmeltWorkflow.metalUnits(graphic:remainder.graphic)==metal-expected*2
        } else {
            consumed=world.items[ore.serial]==nil && world.equipment[ore.serial]==nil
        }
        if !lossMessage,expected>0,gained==expected,consumed {
            inventoryConfirmed=true
            return finish(.success)
        }
        // Loss may leave a smaller pile or remove the source completely. Moving
        // the same serial elsewhere is not evidence that metal was consumed.
        let changed:Bool
        if let current=world.containerItems[ore.serial] {
            changed=current.container==backpack && (current.amount<ore.amount || current.graphic != ore.graphic)
        } else { changed=world.items[ore.serial]==nil && world.equipment[ore.serial]==nil }
        if lossMessage && changed { return finish(.lostMetal) }
        return nil
    }
    private mutating func finish(_ result:Result)->Result { finished=true; return result }
}
