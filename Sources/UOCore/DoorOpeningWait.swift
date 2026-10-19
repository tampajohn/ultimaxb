import Foundation

/// A use request is not proof that a door opened. Wait for that door's geometry
/// to change; callers then rebuild collision and replan, rather than walking blind.
public struct DoorOpeningWait {
    public enum Result: Equatable { case waiting, changed, retry, timedOut }
    private let original: GroundItem
    private var deadline: TimeInterval
    private var sentAt:TimeInterval
    private var retryAt:TimeInterval?
    public private(set) var retries=0
    public init(door: GroundItem, at time: TimeInterval) {
        original = door; deadline = time + 4; sentAt=time
    }
    /// Only an explicit system cooldown response permits a retry. Silence does not.
    public mutating func throttled(at time:TimeInterval) {
        guard time.isFinite,time>=sentAt,time-sentAt<=2,retries<2,retryAt==nil else { return }
        retryAt=time+2; deadline=time+6
    }
    public mutating func didRetry(at time:TimeInterval) {
        guard let retryAt,time>=retryAt,retries<2 else { return }
        retries += 1; self.retryAt=nil; sentAt=time; deadline=time+4
    }
    /// Classic door art uses consecutive closed/open pairs. OUO's item tile
    /// lookup adds its open flag to the base graphic. Limit this to known era
    /// door families; custom graphics have unknown state, not guessed parity.
    public static func isOpenGraphic(_ graphic:Int)->Bool? {
        let families=[0x0675...0x06F4,0x0824...0x0833,0x0839...0x0848,
                      0x084C...0x085B,0x0866...0x0875,0x1FED...0x1FFC]
        guard let family=families.first(where:{$0.contains(graphic)}) else { return nil }
        return (graphic-family.lowerBound)%2 == 1
    }
    public static func geometryChanged(from original: GroundItem, to door: GroundItem) -> Bool {
        door.serial == original.serial && (door.graphic != original.graphic || door.x != original.x || door.y != original.y || door.z != original.z)
    }
    public func result(door: GroundItem?, at time: TimeInterval) -> Result {
        guard time.isFinite, time < deadline else { return .timedOut }
        guard let door, door.serial == original.serial else { return .waiting }
        if Self.geometryChanged(from:original,to:door) { return .changed }
        if let retryAt,time>=retryAt { return .retry }
        return .waiting
    }
}
