import Foundation

/// ANIMDATA.MUL: four-byte group header followed by eight 68-byte records.
/// Offsets are signed, relative to the original static-art graphic.
public struct StaticAnimations {
    private let data:Data
    public init(data:Data) throws {
        guard data.count <= 2 * 1024 * 1024 else { throw AssetError("Animation metadata exceeds limit") }
        self.data = data
    }
    public func graphic(_ base:Int, at time:TimeInterval) -> Int {
        guard (0..<0x4000).contains(base), time.isFinite, time >= 0 else { return base }
        let offset = base * 68 + (base / 8 + 1) * 4
        guard offset + 68 <= data.count else { return base }
        let count = Int(data[offset+65])
        guard (1...64).contains(count) else { return base }
        let interval = Double(max(1,Int(data[offset+66]))) * 0.08
        // Reduce before conversion so very large finite clock values remain safe.
        let cycle = interval * Double(count)
        let frame = min(count-1,Int((time.truncatingRemainder(dividingBy:cycle)/interval).rounded(.down)))
        let graphic = base + Int(Int8(bitPattern:data[offset+frame]))
        return (0..<0x4000).contains(graphic) ? graphic : base
    }
}
