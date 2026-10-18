/// A chat session clears the run latch even while the physical Caps Lock remains on.
public struct RunMode {
    public private(set) var alwaysRun = false
    private var previousCaps = false
    public init() {}
    public mutating func update(capsLock: Bool, chatting: Bool) {
        if chatting { alwaysRun = false }
        else if capsLock != previousCaps { alwaysRun = capsLock }
        previousCaps = capsLock
    }
    public func running(shift: Bool) -> Bool { shift || alwaysRun }
}

public enum MovementPace {
    /// Preserve the requested facing while exhausted; keep run preference intact.
    public static func direction(_ requested:UInt8, stamina:Int?) -> UInt8 {
        if let stamina, stamina <= 1 { return requested & ~0x80 }
        return requested
    }
}
