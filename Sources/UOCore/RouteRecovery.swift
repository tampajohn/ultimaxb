import Foundation

/// Retry local obstructions without spending a whole journey's retry budget.
/// Only server-confirmed positions should be passed to `progress`.
public struct RouteRecovery {
    public private(set) var blocked:Set<WalkPoint> = []
    public private(set) var attempts=0
    private var failureOrigin:WalkPoint?
    public init() {}

    public mutating func reject(_ destination:WalkPoint,from position:WalkPoint)->Bool {
        guard attempts<3 else { return false }
        if failureOrigin == nil { failureOrigin=position }
        blocked.insert(destination)
        attempts += 1
        return true
    }

    public mutating func progress(_ position:WalkPoint) {
        guard let origin=failureOrigin,
              max(abs(position.x-origin.x),abs(position.y-origin.y))>=8 else { return }
        attempts=0; failureOrigin=nil
        // Old dynamic obstacles must not become permanent map walls. Keep only
        // local evidence, with a hard bound for unusually winding journeys.
        blocked=Set(blocked.filter { max(abs($0.x-position.x),abs($0.y-position.y))<=48 })
        if blocked.count>64 { blocked.removeAll() }
    }
}
