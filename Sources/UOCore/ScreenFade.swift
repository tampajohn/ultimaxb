import Foundation

/// Server-requested 0x70/type-4 screen effect. The graphic field selects its style.
/// Timing follows CrossUO's ScreenEffectManager at its nominal 30 ms frame step,
/// expressed in elapsed time so rendering stalls cannot prolong a transition.
public struct ScreenFade {
    public struct Sample: Equatable {
        public let white, opacity: Double
    }
    public let style: Int
    public let started: TimeInterval
    public init(style: Int, at time: TimeInterval) {
        self.style = min(4,max(0,style))
        started = time
    }
    public var rampDuration: TimeInterval {
        0.03 / [0.02,0.02,0.08,0.02,0.15][style]
    }
    public var duration: TimeInterval {
        style == 3 ? rampDuration * 2 + 1.5 : rampDuration
    }
    public func sample(at time: TimeInterval) -> Sample? {
        guard started.isFinite, time.isFinite else { return nil }
        let age = time-started
        guard age >= 0, time < started+duration else { return nil }
        let white = style == 0 || style == 4 ? 0.0 : 1.0
        if age < rampDuration { return Sample(white:white,opacity:age/rampDuration) }
        // White flash, one-second hold, dim to black, half-second hold, release.
        return Sample(white:max(0,1-max(0,age-rampDuration-1)/rampDuration),opacity:1)
    }
}
