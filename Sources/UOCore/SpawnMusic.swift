import Foundation

/// One regional fallback per connection. Any server music event, including
/// silence, owns music for the rest of that connection.
public struct SpawnMusic {
    private var enteredAt:TimeInterval?
    private var resolved=false
    public init() {}
    public mutating func reset() { self=SpawnMusic() }
    public mutating func serverMusicReceived() { resolved=true }
    public mutating func next(regionTrack:Int?,time:TimeInterval)->Int? {
        guard !resolved,time.isFinite else { return nil }
        guard let enteredAt else { self.enteredAt=time; return nil }
        guard time-enteredAt>=1 else { return nil }
        resolved=true
        return regionTrack.flatMap { MusicCatalog.track($0) == nil ? nil:$0 }
    }
}
