import Foundation

/// One server-driven tool action. A workflow schedules repetitions only after a
/// completed result; this object never guesses completion from elapsed time.
public struct AssistantAction {
    public enum State:Equatable {
        case idle
        case waitingForTarget(Int)
        case waitingForResult
        case completed
        case stopped(StopReason)
    }
    public enum StopReason:Equatable {
        case cancelled, disconnected, timeout, unexpectedTarget, serverCancelled
        case invalidSelection, refused, depleted, overweight, missingTool
    }
    public enum Result:Equatable { case success, refused, depleted }
    public enum Command:Equatable {
        case useItem(UInt32)
        case target(TargetRequest,TargetSelection)
        case cancelTarget(TargetRequest)
    }
    public private(set) var state:State = .idle
    private var selections:[TargetSelection] = []
    private var deadline:TimeInterval = 0
    private var timeout:TimeInterval = 10
    private var seen:[TargetRequest] = []

    public init() {}
    /// A single-use instance prevents restarting a timed-out action and consuming
    /// its late cursor as if it belonged to a new request.
    public mutating func start(tool:UInt32,targets:[TargetSelection],at time:TimeInterval,timeout:TimeInterval = 10) throws -> Command {
        guard state == .idle,tool != 0,tool != 0xFFFFFFFF,(1...2).contains(targets.count),
              time.isFinite,timeout.isFinite,(1...60).contains(timeout) else {
            throw AssetError("Invalid assistant tool action")
        }
        selections = targets; self.timeout = timeout
        deadline = time+timeout; state = .waitingForTarget(0)
        return .useItem(tool)
    }
    public mutating func tick(at time:TimeInterval) {
        switch state {
        case .waitingForTarget,.waitingForResult:
            if !time.isFinite || time>=deadline { state = .stopped(.timeout) }
        default: break
        }
    }
    /// The adapter calls this only for the active automation's target stream.
    /// Each accepted cursor produces exactly one target response.
    public mutating func receive(_ request:TargetRequest,at time:TimeInterval)->Command? {
        tick(at:time)
        switch state {
        case .waitingForTarget(let index):
            if request.flags == 3 { state = .stopped(.serverCancelled); return nil }
            guard !seen.contains(request) else {
                state = .stopped(.unexpectedTarget); return .cancelTarget(request)
            }
            seen.append(request)
            let selection = selections[index]
            guard (try? request.response(selection)) != nil else {
                state = .stopped(.invalidSelection); return .cancelTarget(request)
            }
            deadline = time+timeout
            state = index+1<selections.count ? .waitingForTarget(index+1) : .waitingForResult
            return .target(request,selection)
        case .waitingForResult:
            if request.flags == 3 { state = .stopped(.serverCancelled); return nil }
            state = .stopped(.unexpectedTarget); return .cancelTarget(request)
        case .stopped:
            return request.flags == 3 ? nil : .cancelTarget(request)
        case .idle,.completed: return nil
        }
    }
    /// Results must be correlated by the adapter to this tool attempt. Arbitrary
    /// speech, animations and status packets are not completion acknowledgements.
    public mutating func receive(_ result:Result,at time:TimeInterval) {
        tick(at:time)
        guard state == .waitingForResult else { return }
        switch result {
        case .success: state = .completed
        case .refused: state = .stopped(.refused)
        case .depleted: state = .stopped(.depleted)
        }
    }
    public mutating func stop(_ reason:StopReason = .cancelled) {
        switch state {
        case .waitingForTarget,.waitingForResult: state = .stopped(reason)
        default: break
        }
    }
}
