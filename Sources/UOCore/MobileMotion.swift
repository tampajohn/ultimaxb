import Foundation

public struct MobilePresentation: Equatable {
    public let x: Double, y: Double, z: Double
    public let walking: Bool
    public let frame: Int
    public var action: Int? = nil
}

/// Visual interpolation only. Authoritative world positions are never changed.
/// Nearby server updates blend over 200 ms (100 ms with the running flag).
public struct MobileMotion {
    private struct Track {
        var from: MobilePresentation
        var target: WorldMobile
        var started: Double
        var duration: Double
        var animationStarted: Double
        var grace: Double = 0
    }
    private struct ActionTrack {
        let command: MobileAction
        let started: Double
        let frames: Int
        var interval: Double { 0.08 * Double(command.delay+2) }
        func frame(at time:Double)->Int? {
            let elapsed = max(0,Int((time-started)/interval))
            let cycles = command.repeatCount == 0 ? Int.max : command.repeatCount + (command.repeatAnimation ? 1 : 0)
            if elapsed/frames >= cycles { return nil }
            let frame = elapsed%frames
            return command.backward ? frames-1-frame : frame
        }
    }
    private var actions: [UInt32:ActionTrack] = [:]
    public mutating func play(_ command:MobileAction, frames:Int, at time:Double) {
        guard tracks[command.serial] != nil, frames > 0 else { return }
        actions[command.serial] = ActionTrack(command:command,started:time,frames:min(512,command.frameCount > 0 ? min(command.frameCount,frames) : frames))
    }
    private var tracks: [UInt32: Track] = [:]
    public init() {}
    public mutating func update(_ mobiles: [WorldMobile], at time: Double, playerSerial: UInt32? = nil) {
        let serials = Set(mobiles.map(\.serial))
        actions = actions.filter { serials.contains($0.key) && $0.value.frame(at:time) != nil }
        tracks = tracks.filter { serials.contains($0.key) }
        for mobile in mobiles {
            guard var old = tracks[mobile.serial] else {
                tracks[mobile.serial] = Track(from: Self.stationary(mobile), target: mobile,
                                              started: time, duration: 0, animationStarted: time)
                continue
            }
            if old.target.x == mobile.x && old.target.y == mobile.y && old.target.z == mobile.z {
                old.target = mobile
                tracks[mobile.serial] = old
                continue
            }
            actions.removeValue(forKey:mobile.serial)
            let current = Self.sample(old, at: time)
            let distance = max(abs(mobile.x - old.target.x), abs(mobile.y - old.target.y))
            let teleport = distance > 2 || abs(mobile.z - old.target.z) > 20
            let player = mobile.serial == playerSerial
            let baseDuration = (mobile.direction & 0x80 != 0 ? 0.1 : 0.2) * (player ? 2 : 1)
            let interval = time - old.started
            let duration = player && old.duration > 0 && interval >= 0.08 && interval <= 0.65
                ? max(baseDuration, min(baseDuration + 0.1, old.duration * 0.65 + interval * 0.35)) : baseDuration
            tracks[mobile.serial] = Track(from: teleport ? Self.stationary(mobile) : current,
                                          target: mobile, started: time,
                                          duration: teleport ? 0 : duration,
                                          animationStarted: current.walking ? old.animationStarted : time,
                                          grace: player && !teleport ? 0.12 : 0)
        }
    }
    public func presentations(at time: Double) -> [UInt32: MobilePresentation] {
        tracks.mapValues { Self.sample($0, at: time) }.merging(
            actions.compactMapValues { action -> MobilePresentation? in
                guard let track = tracks[action.command.serial], let frame = action.frame(at:time) else { return nil }
                let pose = Self.sample(track,at:time)
                return MobilePresentation(x:pose.x,y:pose.y,z:pose.z,walking:false,frame:frame,action:action.command.action)
            }, uniquingKeysWith: { _,action in action })
    }
    public func isAnimating(at time: Double) -> Bool {
        tracks.values.contains { time < $0.started + $0.duration + $0.grace } || actions.values.contains { $0.frame(at:time) != nil }
    }
    private static func stationary(_ mobile: WorldMobile) -> MobilePresentation {
        MobilePresentation(x: Double(mobile.x), y: Double(mobile.y), z: Double(mobile.z), walking: false, frame: 0)
    }
    private static func sample(_ track: Track, at time: Double) -> MobilePresentation {
        guard track.duration > 0, time < track.started + track.duration + track.grace else { return stationary(track.target) }
        let t = min(1, max(0, (time - track.started) / track.duration))
        func blend(_ a: Double, _ b: Int) -> Double { a + (Double(b) - a) * t }
        return MobilePresentation(x: blend(track.from.x, track.target.x), y: blend(track.from.y, track.target.y),
                                  z: blend(track.from.z, track.target.z), walking: true,
                                  frame: Int(max(0, time - track.animationStarted) * 10) % 512)
    }
}
