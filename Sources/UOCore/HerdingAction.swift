import Foundation

/// One selected animal and destination, using the classic crook's two cursors.
/// The adapter owns tool selection, approach, cancellation and packet transport.
/// Eligibility is decided by the server, never inferred from animal artwork.
public struct HerdingAction {
    public enum State:Equatable {
        case idle, requestingAnimal, requestingDestination, waitingForResult
        case followingOrder, arrived, stopped(AssistantAction.StopReason)
    }
    public private(set) var state:State = .idle
    private var action=AssistantAction()
    private var animalSerial:UInt32=0
    private var destination=WalkPoint(x:0,y:0,z:0)
    private var arrivalDeadline:TimeInterval=0
    public init() {}

    public mutating func start(tool:UInt32,animal:WorldMobile,destination:WalkPoint,time:TimeInterval)throws->AssistantAction.Command {
        guard state == .idle,(1..<0x40000000).contains(animal.serial),!animal.isGhost,
              (0..<65535).contains(destination.x),(0..<65535).contains(destination.y),
              (-128...127).contains(destination.z) else { throw AssetError("Invalid herding selection") }
        let target=TargetSelection(serial:animal.serial,x:animal.x,y:animal.y,z:animal.z,graphic:animal.body)
        let place=TargetSelection(x:destination.x,y:destination.y,z:destination.z,graphic:0)
        let command=try action.start(tool:tool,targets:[target,place],at:time)
        animalSerial=animal.serial;self.destination=destination;state = .requestingAnimal
        return command
    }
    private var active:Bool {
        switch state {
        case .requestingAnimal,.requestingDestination,.waitingForResult,.followingOrder: return true
        default: return false
        }
    }
    public mutating func stop(_ reason:AssistantAction.StopReason = .cancelled) {
        guard active else { return }
        action.stop(reason);state = .stopped(reason)
    }
    public mutating func tick(time:TimeInterval) {
        guard active else { return }
        if state == .followingOrder {
            if !time.isFinite || time>=arrivalDeadline { stop(.timeout) }
        } else {
            action.tick(at:time)
            if case .stopped(let reason)=action.state { state = .stopped(reason) }
        }
    }
    public mutating func receive(_ request:TargetRequest,animal:WorldMobile?,time:TimeInterval)->AssistantAction.Command? {
        tick(time:time)
        if case .stopped=state { return request.flags==3 ? nil:.cancelTarget(request) }
        guard active else { return nil }
        if request.flags==3 { stop(.serverCancelled);return nil }
        if state == .followingOrder { stop(.unexpectedTarget);return .cancelTarget(request) }
        let first=state == .requestingAnimal
        // This profile expects object then location. Do not send a queued animal
        // into an unrelated location cursor from a different manual action.
        guard request.allowsLocation != first else { stop(.unexpectedTarget);return .cancelTarget(request) }
        guard let animal,animal.serial==animalSerial,!animal.isGhost else {
            stop(.invalidSelection);return .cancelTarget(request)
        }
        let command=action.receive(request,at:time)
        switch action.state {
        case .waitingForTarget(1): state = .requestingDestination
        case .waitingForResult: state = .waitingForResult
        case .stopped(let reason): state = .stopped(reason)
        default: break
        }
        if first,case .target = command {
            // Animals can move while the use request is in flight.
            let current=TargetSelection(serial:animal.serial,x:animal.x,y:animal.y,z:animal.z,graphic:animal.body)
            guard (try? request.response(current)) != nil else { stop(.invalidSelection);return .cancelTarget(request) }
            return .target(request,current)
        }
        return command
    }
    public mutating func observe(speech:SpeechMessage?=nil,animal:WorldMobile?,ownsTool:Bool,time:TimeInterval) {
        tick(time:time)
        guard active else { return }
        guard ownsTool else { stop(.missingTool);return }
        guard let animal,animal.serial==animalSerial,!animal.isGhost else { stop(.invalidSelection);return }
        if let speech,state == .requestingDestination || state == .waitingForResult {
            let system=speech.serial == .max && speech.type==6
            let animalBark=speech.serial==animalSerial && speech.type==0
            let refusal=system && ["Target can not be seen.","You don't seem to be able to persuade that to move.","That is not a herdable animal."].contains(speech.text)
            let unavailable=animalBark && ["Someone else is already taming this.","That animal looks tame already.","That being can not be tamed."].contains(speech.text)
            if refusal || unavailable { stop(.refused);return }
            if system,state == .waitingForResult,speech.text=="The animal walks where it was instructed to." {
                action.receive(.success,at:time)
                state = .followingOrder;arrivalDeadline=time+30
            }
        }
        // An accepted order is not evidence that collision/pathfinding succeeded.
        if state == .followingOrder,animal.x==destination.x,animal.y==destination.y,animal.z==destination.z {
            state = .arrived
        }
    }
}
