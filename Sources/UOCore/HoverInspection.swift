import Foundation

/// Rate limits automatic inspection only; deliberate clicks remain immediate.
public struct HoverInspection {
    private var requests:[UInt32:TimeInterval] = [:]
    private var lastRequest:TimeInterval = -.infinity
    public init() {}
    public mutating func shouldRequest(_ serial:UInt32,at time:TimeInterval)->Bool {
        requests = requests.filter { time-$0.value < 2 }
        guard serial != 0, serial != UInt32.max, time-lastRequest >= 0.2,
              requests[serial] == nil else { return false }
        requests[serial] = time; lastRequest = time
        return true
    }
}
