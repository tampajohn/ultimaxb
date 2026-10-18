import Foundation

// MUL frame decoding and direction mapping adapted from ClassicUO
// AnimationsLoader.cs and Animation.cs; see LICENSES/ClassicUO.txt.
public struct AnimationFrame {
    public let sprite: Sprite
    public let centerX: Int, centerY: Int
    public let mirrored: Bool
}

enum AnimationDecoder {
    static func decode(_ raw: Bytes, frame: Int, mirrored: Bool = false) throws -> AnimationFrame? {
        let count = try raw.u32(512)
        guard count > 0, count <= 512, frame >= 0 else { throw AssetError("Invalid animation frame count") }
        try raw.check(516, count * 4)
        let relative = try raw.u32(516 + (frame % count) * 4)
        // Original MULs contain sparse frame tables: zero means no sprite.
        guard relative != 0 else { return nil }
        guard relative >= 4 + count * 4 else { throw AssetError("Animation frame overlaps its index") }
        var cursor = 512 + relative
        func signed(_ value: Int) -> Int { Int(Int16(bitPattern: UInt16(value))) }
        let cx = signed(try raw.u16(cursor)), cy = signed(try raw.u16(cursor + 2))
        let width = try raw.u16(cursor + 4), height = try raw.u16(cursor + 6)
        guard width > 0, height > 0, width <= 1024, height <= 1024 else { throw AssetError("Invalid animation dimensions") }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        cursor += 8
        while true {
            let header = try raw.u32(cursor)
            cursor += 4
            if header == 0x7FFF7FFF { break }
            let length = header & 0xFFF
            func signed10(_ value: Int) -> Int { value & 0x200 != 0 ? value - 1024 : value }
            let x = signed10((header >> 22) & 1023) + cx
            let y = signed10((header >> 12) & 1023) + cy + height
            guard length > 0, x >= 0, y >= 0, y < height, x <= width, length <= width - x else {
                throw AssetError("Animation run is outside its frame")
            }
            try raw.check(cursor, length)
            for i in 0..<length {
                let color = try raw.u16(raw.u8(cursor + i) * 2)
                ArtDecoder.put(color, into: &pixels, at: y * width + x + i)
            }
            cursor += length
        }
        return AnimationFrame(sprite: Sprite(width: width, height: height, rgba: pixels),
                              centerX: cx, centerY: cy, mirrored: mirrored)
    }
}

public final class AnimationAssets {
    private let index: Bytes, data: Bytes
    private struct Key: Hashable { let entry: Int; let frame: Int }
    private var cache: [Key: (AnimationFrame, UInt64)] = [:]
    private var tick: UInt64 = 0
    public private(set) var cacheBytes = 0
    public let cacheLimit: Int
    public init(index: Data, data: Data, cacheLimit: Int = 8 * 1024 * 1024) throws {
        guard cacheLimit >= 0, index.count % 12 == 0 else { throw AssetError("Invalid animation index or cache limit") }
        self.index = Bytes(index); self.data = Bytes(data); self.cacheLimit = cacheLimit
    }
    public func frameCount(body:Int,direction:UInt8,action:Int) throws -> Int? {
        guard body >= 0, body < 2048 else { return nil }
        let groups = body < 200 ? 22 : (body < 400 ? 13 : 35)
        guard (0..<groups).contains(action) else { return nil }
        let base = body < 200 ? body*110 : (body < 400 ? 22000+(body-200)*65 : 35000+(body-400)*175)
        let entry = base+action*5+[3,2,1,0,1,2,3,4][Int(direction&7)]
        guard entry*12+12 <= index.count else { return nil }
        let offset = try index.u32(entry*12), length = try index.u32(entry*12+4)
        guard offset != 0xFFFFFFFF, length != 0, length != 0xFFFFFFFF else { return nil }
        let count = try data.slice(offset,length).u32(512)
        guard count > 0, count <= 512 else { throw AssetError("Invalid animation frame count") }
        return count
    }
    public func frame(body: Int, direction: UInt8, action: Int? = nil, frame: Int = 0) throws -> AnimationFrame? {
        guard body >= 0, body < 2048, frame >= 0, frame < 512 else { return nil }
        let dir = Int(direction & 7)
        let directions = [3, 2, 1, 0, 1, 2, 3, 4]
        let mirror = dir < 3
        let group = action ?? (body < 200 ? 1 : (body < 400 ? 2 : 4))
        let groups = body < 200 ? 22 : (body < 400 ? 13 : 35)
        guard (0..<groups).contains(group) else { return nil }
        let base = body < 200 ? body * 110 : (body < 400 ? 22000 + (body - 200) * 65 : 35000 + (body - 400) * 175)
        let entry = base + group * 5 + directions[dir]
        let key = Key(entry: entry, frame: frame)
        tick &+= 1
        if let (cached, _) = cache[key] {
            cache[key] = (cached, tick)
            return AnimationFrame(sprite: cached.sprite, centerX: cached.centerX, centerY: cached.centerY, mirrored: mirror)
        }
        guard entry * 12 + 12 <= index.count else { return nil }
        let offset = try index.u32(entry * 12), length = try index.u32(entry * 12 + 4)
        if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { return nil }
        guard length <= 16 * 1024 * 1024 else { throw AssetError("Oversized animation record") }
        guard let decoded = try AnimationDecoder.decode(data.slice(offset, length), frame: frame, mirrored: mirror) else { return nil }
        let cost = decoded.sprite.rgba.count
        if cost <= cacheLimit {
            while cacheBytes + cost > cacheLimit, let oldest = cache.min(by: { $0.value.1 < $1.value.1 }) {
                cacheBytes -= oldest.value.0.sprite.rgba.count
                cache.removeValue(forKey: oldest.key)
            }
            cache[key] = (decoded, tick)
            cacheBytes += cost
        }
        return decoded
    }
}
