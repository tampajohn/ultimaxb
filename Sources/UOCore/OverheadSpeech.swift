import Foundation

/// Short-lived, session-only speech. Never persisted or included in telemetry.
public struct OverheadSpeech {
    public struct Entry:Equatable {
        public let serial:UInt32
        public let text:String
        public let expires:TimeInterval
    }
    public private(set) var entries:[Entry] = []
    public init() {}
    public mutating func expire(at time:TimeInterval) {
        entries.removeAll { $0.expires<=time }
    }
    public mutating func append(_ message:SpeechMessage,at time:TimeInterval) {
        expire(at:time)
        guard message.serial != 0,message.serial != 0xFFFFFFFF,!message.text.isEmpty else { return }
        // Labels replace prior labels for this object; speech retains three lines.
        if message.type == 6 { entries.removeAll { $0.serial == message.serial } }
        while entries.filter({ $0.serial == message.serial }).count>=3 {
            entries.remove(at:entries.firstIndex { $0.serial == message.serial }!)
        }
        let text = String(message.text.prefix(512))
        entries.append(Entry(serial:message.serial,text:text,expires:time+max(4,min(12,Double(text.count)*0.06))))
        if entries.count>64 { entries.removeFirst(entries.count-64) }
    }
}
