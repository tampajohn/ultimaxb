import Foundation

public struct LightMask {
    public let width:Int, height:Int
    public let intensity:[UInt8]
}

/// LIGHTIDX.MUL stores offset, length, width and height; LIGHT.MUL stores
/// signed/inverted 5-bit samples. Decode follows ClassicUO LightsLoader
/// (BSD-2-Clause; see LICENSES/ClassicUO.txt).
public final class LightAssets {
    private let index:Bytes, data:Bytes
    public init(index:Data,data:Data) throws {
        guard index.count % 12 == 0 else { throw AssetError("Invalid light index") }
        self.index = Bytes(index); self.data = Bytes(data)
    }
    public func mask(_ id:Int) throws -> LightMask? {
        guard id>=0,id<min(100,index.count/12) else { return nil }
        let p = id*12,offset = try index.u32(p),length = try index.u32(p+4)
        if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { return nil }
        let width = try index.u16(p+8),height = try index.u16(p+10)
        guard (1...512).contains(width),(1...512).contains(height),width*height<=length else { throw AssetError("Invalid light dimensions") }
        try data.check(offset,length)
        var values = [UInt8](); values.reserveCapacity(width*height)
        for i in 0..<width*height {
            let value = try data.u8(offset+i)
            values.append(UInt8((value>31 ? ~value & 31 : value)<<3))
        }
        return LightMask(width:width,height:height,intensity:values)
    }
}
