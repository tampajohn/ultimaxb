import Foundation

public struct SoundEffect: Equatable {
    public let id:Int, flags:UInt8, volume:Int, x:Int, y:Int, z:Int
    public static func decode(_ packet:Data) throws -> SoundEffect {
        guard packet.count == 12, packet.first == 0x54 else { throw LoginProtocolError.malformedPacket }
        var r = PacketReader(packet,offset:1)
        let flags = try r.byte(), id = Int(try r.word()), volume = Int(try r.word())
        let x = Int(try r.word()), y = Int(try r.word()), z = Int(Int16(bitPattern:try r.word()))
        return SoundEffect(id:id,flags:flags,volume:volume,x:x,y:y,z:z)
    }
    public func gain(listenerX:Int,listenerY:Int,range:Int = 18)->Float {
        let distance = max(abs(x-listenerX),abs(y-listenerY))
        guard range >= 0, distance <= range else { return 0 }
        return 1-Float(distance)/Float(range+1)
    }
    public func pan(listenerX:Int,listenerY:Int)->Float {
        // Isometric screen horizontal axis is world X minus world Y.
        max(-1,min(1,Float((x-listenerX)-(y-listenerY))/18))
    }
}

/// Legacy MUL: 40-byte metadata prefix, then 22050 Hz mono signed 16-bit LE PCM.
/// Format checked against ClassicUO SoundsLoader.cs (LICENSES/ClassicUO.txt).
public final class SoundAssets {
    private let index:Bytes, data:Bytes
    private var cache:[Int:(wave:Data,used:UInt64)] = [:]
    private var tick:UInt64 = 0
    public let cacheLimit:Int
    public private(set) var cacheBytes = 0
    public init(index:Data,data:Data,cacheLimit:Int = 4*1024*1024) throws {
        guard index.count%12 == 0, cacheLimit>=0 else { throw AssetError("Invalid sound index or cache limit") }
        self.index=Bytes(index); self.data=Bytes(data); self.cacheLimit=cacheLimit
    }
    public func wave(_ id:Int) throws -> Data? {
        guard id>=0, id<index.count/12 else { return nil }
        tick &+= 1
        if let value = cache[id] { cache[id] = (value.wave,tick); return value.wave }
        let offset = try index.u32(id*12), length = try index.u32(id*12+4)
        if offset == 0xFFFFFFFF || length == 0xFFFFFFFF || length == 0 { return nil }
        guard length>40, length<=2*1024*1024, (length-40)%2 == 0 else { throw AssetError("Invalid sound sample size") }
        let pcm = try data.slice(offset+40,length-40).data
        var wave = Data("RIFF".utf8)
        func u16(_ n:Int) { wave.append(UInt8(n&255)); wave.append(UInt8((n>>8)&255)) }
        func u32(_ n:Int) { u16(n&65535); u16(n>>16) }
        u32(pcm.count+36); wave.append(contentsOf:"WAVEfmt ".utf8)
        u32(16); u16(1); u16(1); u32(22050); u32(44100); u16(2); u16(16)
        wave.append(contentsOf:"data".utf8); u32(pcm.count); wave.append(pcm)
        if wave.count<=cacheLimit {
            while cacheBytes+wave.count>cacheLimit, let oldest = cache.min(by:{$0.value.used<$1.value.used}) {
                cacheBytes-=oldest.value.wave.count; cache.removeValue(forKey:oldest.key)
            }
            cache[id]=(wave,tick); cacheBytes+=wave.count
        }
        return wave
    }
}
