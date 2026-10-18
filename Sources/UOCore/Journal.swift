import Foundation

/// Session-only history; deliberately has no persistence or telemetry integration.
public struct Journal {
    public private(set) var lines:[String] = []
    public private(set) var byteCount = 0
    public let maximumLines:Int, maximumBytes:Int
    public init(maximumLines:Int = 512, maximumBytes:Int = 256*1024) {
        self.maximumLines = max(0,maximumLines); self.maximumBytes = max(0,maximumBytes)
    }
    public mutating func append(_ text:String) {
        guard maximumLines > 0, maximumBytes > 0 else { return }
        // Preserve scalar boundaries even for an oversized server message.
        var line = "", size = 0
        for scalar in text.unicodeScalars {
            let count = scalar.utf8.count
            if size+count > min(4096,maximumBytes) { break }
            line.unicodeScalars.append(scalar); size += count
        }
        guard !line.isEmpty else { return }
        lines.append(line); byteCount += size
        while lines.count > maximumLines || byteCount > maximumBytes {
            byteCount -= lines.removeFirst().utf8.count
        }
    }
    public mutating func clear() { lines.removeAll(); byteCount = 0 }
}
