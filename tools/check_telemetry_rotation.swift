import Foundation

@main struct Check {
    static func main() throws {
        func check(_ value:Bool) { precondition(value) }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url=directory.appendingPathComponent("fixture.jsonl")
        let sink=try TelemetryFile(url:url,limit:40,count:3)
        let records=(0..<20).map { Data("{\"event\":\"fixture\",\"n\":\($0)}\n".utf8) }
        for record in records { check(try sink.append(record)) }
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
        precondition(files.count == 3)
        for path in files {
            let data=try Data(contentsOf:path)
            precondition(data.count<=40 && data.last == 10)
            for line in data.split(separator:10) { _ = try JSONSerialization.jsonObject(with:Data(line)) }
        }
        check(try Data(contentsOf:url) == records[19])
        check(try Data(contentsOf:directory.appendingPathComponent("fixture.1.jsonl")) == records[18])
        check(try Data(contentsOf:directory.appendingPathComponent("fixture.2.jsonl")) == records[17])
        check(try !sink.append(Data(repeating:65,count:41)))
        let final=Data("{\"event\":\"last\"}\n".utf8)
        check(try sink.append(final))
        check(try Data(contentsOf:url) == final)
        do { _ = try TelemetryFile(url:url); preconditionFailure("Existing logs must not be truncated") }
        catch CocoaError.fileWriteFileExists { }
        let singleURL=directory.appendingPathComponent("single.jsonl")
        let single=try TelemetryFile(url:singleURL,limit:40,count:1)
        try single.append(records[0]); try single.append(records[1])
        check(try Data(contentsOf:singleURL) == records[1])
        print("Telemetry rotation bounds, record integrity, oversized record recovery and existing-file protection passed")
    }
}
