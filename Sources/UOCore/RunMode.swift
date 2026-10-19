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

/// Long-distance travel saves a small stamina reserve for nearby threats.
/// Manual movement remains governed by MovementPace and the user's run controls.
public struct TravelPace {
    public enum Mode:String { case cruising, conserving, escaping, exhausted }
    public private(set) var mode:Mode = .cruising
    private var conserving=false
    private var escapeUntil:Double = -.infinity
    public init() {}
    public static func reserve(maximum:Int)->Int {
        min(max(0,maximum-2),max(3,min(10,(maximum+3)/4)))
    }
    public mutating func direction(_ requested:UInt8,stamina:Int?,maximum:Int?,enemyDistances:[Int],at time:Double)->UInt8 {
        guard let stamina,let maximum,maximum>0,time.isFinite else {
            mode = .cruising
            return MovementPace.direction(requested,stamina:stamina)
        }
        let reserve=Self.reserve(maximum:maximum)
        let resume=min(maximum,reserve+max(2,min(5,maximum/5)))
        if stamina<=reserve { conserving=true }
        else if stamina>=resume { conserving=false }
        // A close attacker or a nearby group warrants spending the reserve.
        let threatened=enemyDistances.contains { $0<=4 } || enemyDistances.filter { $0<=8 }.count>=2
        if threatened { escapeUntil=time+3 }
        if stamina<=1 { mode = .exhausted; return requested & ~0x80 }
        if time<escapeUntil { mode = .escaping; return requested | 0x80 }
        if conserving { mode = .conserving; return requested & ~0x80 }
        mode = .cruising; return requested
    }
}
