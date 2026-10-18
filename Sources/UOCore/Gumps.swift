import Foundation

/// Original GUMPIDX/GUMPART container and interface artwork.
public final class GumpAssets {
    private let index: Bytes, data: Bytes
    private let patches: Bytes?
    private var records: [Int: (offset: Int, length: Int, size: Int)] = [:]
    public init(index: Data, data: Data, verdata: Data? = nil) throws {
        guard index.count % 12 == 0 else { throw AssetError("Invalid gump index") }
        self.index = Bytes(index); self.data = Bytes(data)
        patches = verdata.map(Bytes.init)
        if let patches {
            let count = try patches.u32(0)
            try patches.check(4, count * 20)
            for i in 0..<count {
                let p = 4 + i * 20
                guard try patches.u32(p) == 12 else { continue }
                let id = try patches.u32(p + 4)
                let offset = try patches.u32(p + 8), length = try patches.u32(p + 12)
                let size = try patches.u32(p + 16)
                try patches.check(offset, length)
                records[id] = (offset, length, size)
            }
        }
    }
    public func sprite(_ id: Int) throws -> Sprite? {
        guard id >= 0 else { return nil }
        if let record = records[id], let patches {
            guard record.length > 0 else { return nil }
            return try Self.decode(patches.slice(record.offset, record.length),
                                   width: record.size >> 16, height: record.size & 0xFFFF)
        }
        guard id < index.count / 12 else { return nil }
        let p = id * 12
        let offset = try index.u32(p), length = try index.u32(p + 4)
        if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { return nil }
        let size = try index.u32(p + 8)
        return try Self.decode(data.slice(offset, length), width: size >> 16, height: size & 0xFFFF)
    }
    static func decode(_ raw: Bytes, width: Int, height: Int) throws -> Sprite {
        guard (1...2048).contains(width), (1...2048).contains(height) else { throw AssetError("Invalid gump dimensions") }
        try raw.check(0, height * 4)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            var position = try raw.u32(y * 4) * 4
            guard position >= height * 4 else { throw AssetError("Gump row overlaps lookup table") }
            var x = 0
            while x < width {
                let color = try raw.u16(position), run = try raw.u16(position + 2)
                guard run > 0, run <= width - x else { throw AssetError("Invalid gump run") }
                if color != 0 {
                    for column in x..<x + run { ArtDecoder.put(color, into: &pixels, at: y * width + column) }
                }
                x += run; position += 4
            }
        }
        return Sprite(width: width, height: height, rgba: pixels)
    }
}
