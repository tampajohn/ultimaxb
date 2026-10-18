import AppKit
import Foundation

/// Local metadata-only diagnostics. Never pass credentials, field values, chat,
/// character names, or raw packet payloads to this logger.
@MainActor
final class Telemetry {
    static let shared = Telemetry()
    private var handle: FileHandle?
    private var bytes = 0
    private let limit = 16 * 1024 * 1024
    private var monitor: Any?
    let path: String
    private init() {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/telemetry", isDirectory: true)
        let name = "session-\(Int(Date().timeIntervalSince1970))-\(ProcessInfo.processInfo.processIdentifier).jsonl"
        let file = directory.appendingPathComponent(name)
        path = file.path
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil)
            handle = try FileHandle(forWritingTo: file)
        } catch { print("Telemetry unavailable: \(error)") }
    }
    func record(_ event: String, _ fields: [String: Any] = [:]) {
        guard let handle, bytes < limit else { return }
        var row = fields
        row["event"] = event
        row["time"] = ISO8601DateFormatter().string(from: Date())
        row["uptime"] = ProcessInfo.processInfo.systemUptime
        guard JSONSerialization.isValidJSONObject(row),
              var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        data.append(10)
        do { try handle.write(contentsOf: data); bytes += data.count }
        catch { self.handle = nil }
    }
    func installClickMonitor() {
        guard monitor == nil else { return }
        record("app_started", ["protocol": "1.25.32"])
        print("Local telemetry: \(path)")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { event in
            MainActor.assumeIsolated {
                if let content = event.window?.contentView {
                    let point = content.convert(event.locationInWindow, from: nil)
                    let target = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
                    self.record("pointer", ["type": event.type.rawValue, "x": Int(point.x), "y": Int(point.y),
                                             "target": target.map { String(describing: type(of: $0)) } ?? "none"])
                }
            }
            return event
        }
    }
}
