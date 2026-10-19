import Foundation

/// Bounded, server-driven work-zone scheduling. The adapter supplies collision-
/// checked routes, authoritative positions, owned-tool checks and correlated
/// results. This type never interprets arbitrary speech as harvesting success.
public struct HarvestWorkflow {
    public struct Zone:Equatable {
        public let minX:Int, minY:Int, maxX:Int, maxY:Int
        public init(x1:Int,y1:Int,x2:Int,y2:Int) throws {
            guard (0..<6144).contains(x1),(0..<6144).contains(x2),
                  (0..<4096).contains(y1),(0..<4096).contains(y2),
                  abs(x1-x2)<128,abs(y1-y2)<128 else { throw AssetError("Invalid harvest zone") }
            minX=min(x1,x2); maxX=max(x1,x2); minY=min(y1,y2); maxY=max(y1,y2)
        }
        public func contains(x:Int,y:Int)->Bool { (minX...maxX).contains(x) && (minY...maxY).contains(y) }
    }
    public struct Site:Equatable {
        public let target:TargetSelection
        public let standing:WalkPoint
        public init(target:TargetSelection,standing:WalkPoint) { self.target=target; self.standing=standing }
    }
    public enum State:Equatable {
        case idle, ready, travelling, working, coolingDown, paused, completed
        case stopped(AssistantAction.StopReason)
    }
    public enum Command:Equatable { case route([WalkPoint]), tool(AssistantAction.Command) }
    public private(set) var state:State = .idle
    public private(set) var successfulActions=0
    public private(set) var currentSite:Site?
    private var zone:Zone?
    private var sites:[Site]=[]
    private var index=0
    private var tool:UInt32=0
    private var limit=0
    private var emptyAttempts=0
    private var emptyLimit=5
    private var action=AssistantAction()
    private var readyAt:TimeInterval=0
    private var travelDeadline:TimeInterval=0
    private var pauseRequested=false
    public init() {}
    public mutating func start(zone:Zone,sites:[Site],tool:UInt32,successfulActions:Int,maxConsecutiveEmptyAttempts:Int=5) throws {
        guard state == .idle,tool != 0,tool != .max,(1...256).contains(sites.count),
              (1...10000).contains(successfulActions),(1...100).contains(maxConsecutiveEmptyAttempts),sites.allSatisfy({ site in
                  zone.contains(x:site.target.x,y:site.target.y) && zone.contains(x:site.standing.x,y:site.standing.y) &&
                  !ToolReach.needsApproach(playerX:site.standing.x,playerY:site.standing.y,target:site.target) &&
                  (-128...127).contains(site.standing.z) && (-128...127).contains(site.target.z) &&
                  (0...65535).contains(site.target.graphic) && site.target.serial != .max
              }) else { throw AssetError("Invalid harvest workflow") }
        self.zone=zone; self.sites=sites; self.tool=tool; limit=successfulActions; emptyLimit=maxConsecutiveEmptyAttempts
        state = .ready; currentSite=sites[0]
    }
    /// A pause drains the current action; Stop is the immediate interruption.
    public mutating func pause() {
        switch state {
        case .ready,.coolingDown: state = .paused
        case .travelling,.working: pauseRequested=true
        default: break
        }
    }
    public mutating func resume() { if state == .paused { pauseRequested=false; state = .coolingDown } }
    /// The adapter must cancel its route when this becomes stopped/disconnected.
    public mutating func stop(_ reason:AssistantAction.StopReason = .cancelled) {
        switch state {
        case .ready,.travelling,.working,.coolingDown,.paused:
            action.stop(reason); state = .stopped(reason)
        default: break
        }
    }
    /// A confirmed unusable site or failed approach does not revoke the zone.
    public mutating func skipCurrentSite(time:TimeInterval) {
        guard state == .travelling || state == .working || state == .ready else { return }
        action.stop(.unreachable); emptyAttempts=0; index += 1
        if index>=sites.count { state = .completed; currentSite=nil; return }
        currentSite=sites[index]; readyAt=time+1
        state = pauseRequested ? .paused : .coolingDown
    }
    public mutating func next(position:WalkPoint,ownsTool:Bool,overweight:Bool,time:TimeInterval,
                              route:(WalkPoint,WalkPoint)->[WalkPoint]?)->Command? {
        switch state { case .idle,.completed,.stopped: return nil; default: break }
        guard ownsTool else { stop(.missingTool); return nil }
        guard !overweight else { stop(.overweight); return nil }
        guard time.isFinite else { stop(.timeout); return nil }
        guard let zone,zone.contains(x:position.x,y:position.y) else { stop(.invalidSelection); return nil }
        if state == .paused { return nil }
        if state == .working {
            action.tick(at:time)
            if case .stopped(let reason)=action.state { stop(reason) }
            return nil
        }
        if state == .travelling {
            guard time<travelDeadline else { skipCurrentSite(time:time); return nil }
            guard position==currentSite?.standing else { return nil }
            state = pauseRequested ? .paused : .ready
            if state == .paused { return nil }
        }
        if state == .coolingDown {
            guard time>=readyAt else { return nil }
            state = .ready
        }
        guard state == .ready else { return nil }
        while index<sites.count {
            let site=sites[index]; currentSite=site
            if position==site.standing {
                action=AssistantAction()
                do {
                    let command=try action.start(tool:tool,targets:[site.target],at:time)
                    state = .working; return .tool(command)
                } catch { stop(.invalidSelection); return nil }
            }
            if let steps=route(position,site.standing),!steps.isEmpty,steps.count<=512,steps.last==site.standing {
                var previous=position
                let valid=steps.allSatisfy { step in
                    defer { previous=step }
                    return zone.contains(x:step.x,y:step.y) && max(abs(step.x-previous.x),abs(step.y-previous.y))==1
                }
                if valid {
                    state = .travelling; travelDeadline=time+min(180,Double(steps.count)+10)
                    return .route(steps)
                }
            }
            // Unreachable sites are skipped once. Never retry a rejected path
            // forever or accept a shortcut that leaves the work zone.
            index += 1
        }
        currentSite=nil; stop(.unreachable)
        return nil
    }
    public mutating func receive(_ request:TargetRequest,time:TimeInterval)->Command? {
        if case .stopped = state { return request.flags==3 ? nil : .tool(.cancelTarget(request)) }
        guard state == .working else {
            switch state {
            case .ready,.travelling,.coolingDown,.paused:
                stop(request.flags == 3 ? .serverCancelled : .unexpectedTarget)
                return request.flags == 3 ? nil : .tool(.cancelTarget(request))
            default: return nil
            }
        }
        let command=action.receive(request,at:time)
        if case .stopped(let reason)=action.state { stop(reason) }
        return command.map(Command.tool)
    }
    public mutating func receive(_ result:AssistantAction.Result,time:TimeInterval) {
        guard state == .working else { return }
        action.receive(result,at:time)
        switch action.state {
        case .completed:
            successfulActions += 1; emptyAttempts=0
            if successfulActions>=limit { state = .completed; return }
        case .completedWithoutYield:
            emptyAttempts += 1
            if emptyAttempts>=emptyLimit { stop(.noProgress); return }
        case .stopped(.unreachable):
            skipCurrentSite(time:time); return
        case .stopped(.depleted):
            emptyAttempts=0; index += 1
            if index>=sites.count { state = .completed; currentSite=nil; return }
            currentSite=sites[index]
        case .stopped(let reason): stop(reason); return
        default: return
        }
        readyAt=time+1
        state = pauseRequested ? .paused : .coolingDown
    }
}
