import Foundation

/// Bounded, whole-record rotation. The base file is always the newest chunk.
final class TelemetryFile {
    private let url:URL
    private let limit:Int
    private let count:Int
    private var handle:FileHandle?
    private var bytes=0
    init(url:URL,limit:Int = 16*1024*1024,count:Int = 3) throws {
        precondition(limit>0 && count>0)
        self.url=url; self.limit=limit; self.count=count
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        guard !FileManager.default.fileExists(atPath:url.path) else { throw CocoaError(.fileWriteFileExists) }
        try openNew()
    }
    deinit { try? handle?.close() }
    private func chunk(_ index:Int)->URL {
        index == 0 ? url : url.deletingPathExtension().appendingPathExtension("\(index).jsonl")
    }
    private func openNew() throws {
        guard FileManager.default.createFile(atPath:url.path,contents:nil) else { throw CocoaError(.fileWriteUnknown) }
        handle=try FileHandle(forWritingTo:url); bytes=0
    }
    /// Oversized records are dropped whole; subsequent ordinary records continue.
    @discardableResult func append(_ data:Data) throws -> Bool {
        guard data.count<=limit else { return false }
        if bytes+data.count>limit {
            try handle?.close(); handle=nil
            let fm=FileManager.default
            let oldest=chunk(count-1)
            if fm.fileExists(atPath:oldest.path) { try fm.removeItem(at:oldest) }
            if count>1 {
                for index in stride(from:count-2,through:0,by:-1) where fm.fileExists(atPath:chunk(index).path) {
                    try fm.moveItem(at:chunk(index),to:chunk(index+1))
                }
            }
            try openNew()
        }
        guard let handle else { throw CocoaError(.fileWriteUnknown) }
        try handle.write(contentsOf:data); bytes += data.count
        return true
    }
}
