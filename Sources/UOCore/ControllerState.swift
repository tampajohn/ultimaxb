import Foundation

/// Controller values use screen-relative directions: positive Y is up.
public struct ControllerState {
    public enum Action: Int, CaseIterable, Sendable { case use, cancel, backpack, character, tool }
    public struct Output {
        public let direction: UInt8?
        public let actions: Set<Action>
        public var cursorX: Double = 0
        public var cursorY: Double = 0
    }
    public var deadzone: Double
    public var runThreshold: Double
    private var armed = false
    private var previous = Set<Action>()
    public init(deadzone: Double = 0.25, runThreshold: Double = 0.5) {
        self.deadzone = deadzone; self.runThreshold = runThreshold
    }
    public mutating func suspend() { armed = false; previous.removeAll() }
    public mutating func sample(x: Double, y: Double, trigger: Double, buttons: Set<Action>, enabled: Bool, cursorX: Double = 0, cursorY: Double = 0) -> Output {
        guard enabled, x.isFinite, y.isFinite, trigger.isFinite, cursorX.isFinite, cursorY.isFinite else {
            suspend(); return Output(direction: nil, actions: [])
        }
        let magnitude = hypot(x, y)
        // Require neutral controls after reconnect, focus changes, or closing chat.
        if !armed {
            if magnitude <= deadzone && trigger <= runThreshold && hypot(cursorX, cursorY) <= deadzone && buttons.isEmpty { armed = true }
            return Output(direction: nil, actions: [])
        }
        let pressed = buttons.subtracting(previous)
        previous = buttons
        let direction: UInt8? = magnitude > deadzone
            ? UInt8((Int((atan2(-y, x) / (.pi / 4)).rounded()) + 9) % 8) | (trigger > runThreshold ? 0x80 : 0)
            : nil
        let radius = hypot(cursorX, cursorY)
        let speed = radius > deadzone ? min(1, (radius-deadzone)/(1-deadzone)) : 0
        return Output(direction: direction, actions: pressed,
                      cursorX: radius > 0 ? cursorX/radius*speed : 0,
                      cursorY: radius > 0 ? -cursorY/radius*speed : 0)
    }
}
