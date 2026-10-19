import Foundation

/// Retry local obstructions without spending a whole journey's retry budget.
/// Only server-confirmed positions should be passed to `progress`.
public struct RouteRecovery {
    private var fixedBlocks:Set<WalkPoint> = []
    private var mobileBlocks:[WalkPoint:TimeInterval] = [:]
    public var blocked:Set<WalkPoint> { fixedBlocks.union(mobileBlocks.keys) }
    public private(set) var mobileAttempts=0
    public private(set) var retryAt:TimeInterval=0
    public var hasTemporaryBlocks:Bool { !mobileBlocks.isEmpty }
    public mutating func waitForTemporaryBlocks() {
        if let expiry=mobileBlocks.values.min() { retryAt=expiry }
    }
    public mutating func expire(at time:TimeInterval) { mobileBlocks=mobileBlocks.filter { $0.value>time } }
    public private(set) var attempts=0
    private var failureOrigin:WalkPoint?
    public init() {}

    public mutating func reject(_ destination:WalkPoint,from position:WalkPoint,temporary:Bool=false,at time:TimeInterval=0)->Bool {
        if temporary {
            guard mobileAttempts<12 else { return false }
            if failureOrigin == nil { failureOrigin=position }
            mobileAttempts += 1
            mobileBlocks[destination]=time+2
            retryAt=time+0.75
            return true
        }
        guard attempts<3 else { return false }
        if failureOrigin == nil { failureOrigin=position }
        fixedBlocks.insert(destination)
        attempts += 1
        return true
    }

    public mutating func progress(_ position:WalkPoint) {
        guard let origin=failureOrigin,
              max(abs(position.x-origin.x),abs(position.y-origin.y))>=8 else { return }
        attempts=0; mobileAttempts=0; failureOrigin=nil
        // Old dynamic obstacles must not become permanent map walls. Keep only
        // local evidence, with a hard bound for unusually winding journeys.
        fixedBlocks=Set(fixedBlocks.filter { max(abs($0.x-position.x),abs($0.y-position.y))<=48 })
        if fixedBlocks.count>64 { fixedBlocks.removeAll() }
    }
}
