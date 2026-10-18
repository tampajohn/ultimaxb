import Foundation

/// A use request is not proof that a door opened. Wait for that door's geometry
/// to change; callers then rebuild collision and replan, rather than walking blind.
public struct DoorOpeningWait {
    public enum Result: Equatable { case waiting, changed, timedOut }
    private let original: GroundItem
    private let deadline: TimeInterval
    public init(door: GroundItem, at time: TimeInterval) {
        original = door; deadline = time + 4
    }
    public func result(door: GroundItem?, at time: TimeInterval) -> Result {
        guard time.isFinite, time < deadline else { return .timedOut }
        guard let door, door.serial == original.serial else { return .waiting }
        return door.graphic != original.graphic || door.x != original.x || door.y != original.y || door.z != original.z ? .changed : .waiting
    }
}
