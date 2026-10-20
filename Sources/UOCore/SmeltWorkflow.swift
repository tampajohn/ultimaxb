import Foundation

/// Confirmed ore combining and bounded smelting attempts at a live forge. The
/// adapter exclusively owns the target stream and stops this workflow for any
/// manual action, danger, disconnect or overlapping inventory transaction.
public struct SmeltWorkflow {
    public enum State:Equatable { case idle, ready, working, coolingDown, completed, stopped(AssistantAction.StopReason) }
    public private(set) var state:State = .idle
    public private(set) var successes=0
    public private(set) var skipped=0
    public private(set) var losses=0
    public private(set) var combined=0
    public private(set) var lastObservation:[String:Int]=[:]
    public var combining:Bool { mergePair != nil }
    private var prepare=true
    private var mergePair:(ContainerItem,ContainerItem)?
    private var mergeTargeted=false
    private var mergeDeadline:TimeInterval=0
    private var pileFailures=0
    private var piles:[ContainerItem]=[]
    private var index=0
    private var bag:UInt32=0
    private var forge:GroundItem?
    private var action=AssistantAction()
    private var outcome:SmeltOutcome?
    private var readyAt:TimeInterval=0
    // Classic mining.m creates 1, 2, or 4 metal units per pile shape.
    // Combining preserves metal units, not the displayed stack count.
    public static func metalUnits(graphic:Int)->Int {
        switch graphic { case 0x19B7: return 1; case 0x19B8,0x19BA: return 2; case 0x19B9: return 4; default: return 0 }
    }
    public init() {}
    public mutating func start(backpack:UInt32,forge:GroundItem,world:WorldState,combineOre:Bool = true) throws {
        guard state == .idle,backpack != 0,backpack != .max,
              forge.serial != 0,forge.serial != .max,SmeltOutcome.isForge(forge.graphic),
              world.items[forge.serial]==forge else { throw AssetError("Select a visible forge") }
        let candidates=world.containerItems.values.filter { $0.container==backpack && (0x19B7...0x19BA).contains($0.graphic) }.sorted { $0.serial<$1.serial }
        guard !candidates.isEmpty,candidates.count<=256 else { throw AssetError("Open a backpack containing ore first") }
        bag=backpack; self.forge=forge; piles=candidates; prepare=combineOre; state = .ready
    }
    public mutating func stop(_ reason:AssistantAction.StopReason = .cancelled) {
        switch state {
        case .ready,.working,.coolingDown: lastObservation=outcome?.diagnostics ?? [:]; action.stop(reason); outcome=nil; state = .stopped(reason)
        default: break
        }
    }
    private func validForge(world:WorldState,position:WalkPoint)->Bool {
        guard let forge,let current=world.items[forge.serial],current.graphic==forge.graphic,
              current.x==forge.x,current.y==forge.y,current.z==forge.z else { return false }
        return max(abs(position.x-forge.x),abs(position.y-forge.y))<=3
    }
    public mutating func next(world:WorldState,position:WalkPoint,time:TimeInterval)->AssistantAction.Command? {
        switch state { case .idle,.completed,.stopped: return nil; default: break }
        guard time.isFinite else { stop(.timeout); return nil }
        guard validForge(world:world,position:position) else { stop(.unreachable); return nil }
        if state == .working {
            observe(world:world,time:time)
            if state == .working {
                action.tick(at:time)
                if case .stopped(let reason)=action.state { stop(reason) }
            }
            return nil
        }
        if state == .coolingDown {
            guard time>=readyAt else { return nil }
            state = .ready
        }
        if prepare {
            // Match metal hue across pile shapes; validate the server result
            // using conserved metal units rather than raw stack amounts.
            for source in piles {
                guard world.containerItems[source.serial]==source else { stop(.missingTool); return nil }
                if let destination=piles.first(where:{$0.serial != source.serial && $0.hue==source.hue && $0.amount*Self.metalUnits(graphic:$0.graphic)+source.amount*Self.metalUnits(graphic:source.graphic)<=65535}) {
                    mergePair=(source,destination); mergeTargeted=false; action=AssistantAction()
                    do {
                        let command=try action.start(tool:source.serial,targets:[.init(serial:destination.serial,x:destination.x,y:destination.y,z:0,graphic:destination.graphic)],at:time)
                        state = .working; return command
                    } catch { stop(.invalidSelection); return nil }
                }
            }
            prepare=false
        }
        guard index<piles.count else { state = .completed; return nil }
        // A changed/moved source is not a new pile to silently substitute.
        guard world.containerItems[piles[index].serial]==piles[index] else { stop(.missingTool); return nil }
        action=AssistantAction()
        let target=TargetSelection(serial:forge!.serial,x:forge!.x,y:forge!.y,z:forge!.z,graphic:forge!.graphic)
        do {
            let command=try action.start(tool:piles[index].serial,targets:[target],at:time)
            state = .working; return command
        } catch { stop(.invalidSelection); return nil }
    }
    public mutating func receive(_ request:TargetRequest,world:WorldState,position:WalkPoint,time:TimeInterval)->AssistantAction.Command? {
        if case .stopped=state { return request.flags==3 ? nil:.cancelTarget(request) }
        guard state == .working,validForge(world:world,position:position) else {
            stop(.unexpectedTarget); return request.flags==3 ? nil:.cancelTarget(request)
        }
        let command=action.receive(request,at:time)
        if let pair=mergePair {
            guard world.containerItems[pair.0.serial]==pair.0,world.containerItems[pair.1.serial]==pair.1 else { stop(.missingTool); return .cancelTarget(request) }
            if case .target=command { mergeTargeted=true; mergeDeadline=time+10 }
            if case .stopped(let reason)=action.state { stop(reason) }
            return command
        }
        if case .target=command {
            guard world.containerItems[piles[index].serial]==piles[index],
                  let tracker=try? SmeltOutcome(ore:piles[index],backpack:bag,world:world,time:time) else {
                stop(.missingTool); return .cancelTarget(request)
            }
            outcome=tracker
        }
        if case .stopped(let reason)=action.state { stop(reason) }
        return command
    }
    public mutating func observe(speech:SpeechMessage?=nil,world:WorldState,time:TimeInterval) {
        guard state == .working else { return }
        if let pair=mergePair,mergeTargeted {
            guard time.isFinite,time<mergeDeadline else { stop(.timeout); return }
            let a=world.containerItems[pair.0.serial],b=world.containerItems[pair.1.serial]
            let survivor=a ?? b,removed=a == nil ? pair.0.serial:pair.1.serial
            if (a == nil || b == nil),let survivor,
               world.items[removed]==nil,world.equipment[removed]==nil,
               survivor.container==bag,Self.metalUnits(graphic:survivor.graphic)>0,survivor.hue==pair.0.hue,
               survivor.amount*Self.metalUnits(graphic:survivor.graphic)==pair.0.amount*Self.metalUnits(graphic:pair.0.graphic)+pair.1.amount*Self.metalUnits(graphic:pair.1.graphic) {
                piles.removeAll { $0.serial==pair.0.serial || $0.serial==pair.1.serial }
                piles.append(survivor); piles.sort { $0.serial<$1.serial }
                mergePair=nil; mergeTargeted=false; combined += 1
                readyAt=time+1; state = .coolingDown
            }
            return
        }
        guard var tracker=outcome else { return }
        let result=tracker.observe(speech:speech,world:world,time:time)
        outcome=tracker
        guard let result else { return }
        switch result {
        case .success: successes += 1; pileFailures=0
        case .insufficientOre: skipped += 1; pileFailures=0
        case .lostMetal:
            losses += 1; pileFailures += 1
            if let remaining=world.containerItems[piles[index].serial],
               remaining.container==bag,remaining.hue==piles[index].hue,
               (0x19B7...0x19BA).contains(remaining.graphic),remaining.amount>0,pileFailures<3 {
                piles[index]=remaining; outcome=nil; readyAt=time+2; state = .coolingDown
                return
            }
            skipped += 1; pileFailures=0
        case .refused: stop(.refused); return
        case .unreachable: stop(.unreachable); return
        }
        outcome=nil; index += 1
        if index==piles.count { state = .completed }
        else { readyAt=time+1; state = .coolingDown }
    }
}
