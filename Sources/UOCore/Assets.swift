import Foundation

public struct AssetError: Error, CustomStringConvertible {
    public let description: String
    public init(_ message: String) { description = message }
}

// Byte reads deliberately avoid alignment and native-endian assumptions.
struct Bytes {
    let data: Data
    var count: Int { data.count }
    init(_ data: Data) { self.data = data }
    func check(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset <= count, length <= count - offset else {
            throw AssetError("Truncated asset record at \(offset), length \(length), file size \(count)")
        }
    }
    func u8(_ offset: Int) throws -> Int {
        try check(offset, 1)
        return Int(data[data.startIndex + offset])
    }
    func i8(_ offset: Int) throws -> Int {
        Int(Int8(bitPattern: UInt8(try u8(offset))))
    }
    func u16(_ offset: Int) throws -> Int {
        try u8(offset) | (u8(offset + 1) << 8)
    }
    func u32(_ offset: Int) throws -> Int {
        try u16(offset) | (u16(offset + 2) << 16)
    }
    func slice(_ offset: Int, _ length: Int) throws -> Bytes {
        try check(offset, length)
        return Bytes(data.subdata(in: offset..<offset + length))
    }
}

public struct Sprite {
    public let width: Int
    public let height: Int
    // RGBA bytes, top-to-bottom, with binary transparency.
    public let rgba: [UInt8]
}

enum ArtDecoder {
    static func put(_ color: Int, into pixels: inout [UInt8], at pixel: Int) {
        let p = pixel * 4
        pixels[p] = UInt8(((color >> 10) & 31) * 255 / 31)
        pixels[p + 1] = UInt8(((color >> 5) & 31) * 255 / 31)
        pixels[p + 2] = UInt8((color & 31) * 255 / 31)
        pixels[p + 3] = 255
    }
    static func land(_ raw: Bytes) throws -> Sprite {
        try raw.check(0, 2024)
        var pixels = [UInt8](repeating: 0, count: 44 * 44 * 4)
        var offset = 0
        for y in 0..<44 {
            let half = min(y + 1, 44 - y)
            for x in (22 - half)..<(22 + half) {
                put(try raw.u16(offset), into: &pixels, at: y * 44 + x)
                offset += 2
            }
        }
        return Sprite(width: 44, height: 44, rgba: pixels)
    }
    static func item(_ raw: Bytes) throws -> Sprite {
        let width = try raw.u16(4), height = try raw.u16(6)
        guard (1...1024).contains(width), (1...1024).contains(height) else {
            throw AssetError("Invalid static dimensions \(width)x\(height)")
        }
        try raw.check(8, height * 2)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            var pos = try 8 + height * 2 + raw.u16(8 + y * 2) * 2
            var x = 0
            while true {
                let skip = try raw.u16(pos), count = try raw.u16(pos + 2)
                pos += 4
                if skip == 0 && count == 0 { break }
                x += skip
                guard x + count <= width else { throw AssetError("Static run extends beyond row") }
                try raw.check(pos, count * 2)
                for i in 0..<count {
                    let value = try raw.u16(pos + i * 2)
                    if value != 0 { put(value, into: &pixels, at: y * width + x + i) }
                }
                pos += count * 2
                x += count
            }
        }
        return Sprite(width: width, height: height, rgba: pixels)
    }
}

public struct WorldTile {
    public let x: Int, y: Int, z: Int, art: Int, hue: Int
    public var effectAge: TimeInterval? = nil
    public var effectPose: MobilePresentation? = nil
    public var corpseBody:Int? = nil
    public var corpseDirection:UInt8 = 0
    public var corpseEquipment:[EquippedItem] = []
    public var isStatic: Bool { art >= 0x4000 }
}

struct DrawEntry {
    let tile: WorldTile
    let priority: Int
    let originalIndex: Int

    static func mobile(_ mobile: WorldMobile, presentation: MobilePresentation?, index: Int) -> DrawEntry {
        // A walking sprite overlaps both cells until it reaches the next tile.
        // Use the forward cell of that footprint, including when walking toward
        // smaller coordinates; sorting at the destination lets the old floor
        // paint over the still-interpolating body.
        let x = Int(ceil(presentation?.x ?? Double(mobile.x)))
        let y = Int(ceil(presentation?.y ?? Double(mobile.y)))
        let z = max(mobile.z, Int(ceil(presentation?.z ?? Double(mobile.z))))
        return DrawEntry(tile: WorldTile(x: x, y: y, z: z, art: 0x4000, hue: mobile.hue),
                         priority: z + 1, originalIndex: index)
    }
    static func precedes(_ a: DrawEntry, _ b: DrawEntry) -> Bool {
        let l = a.tile, r = b.tile
        if l.x + l.y != r.x + r.y { return l.x + l.y < r.x + r.y }
        // Finish one world cell before drawing the next cell on the diagonal.
        // Sorting all cells by Z first can interleave unrelated walls and bridge pieces.
        if l.x != r.x { return l.x < r.x }
        if a.priority != b.priority { return a.priority < b.priority }
        if l.isStatic != r.isStatic { return !l.isStatic }
        return a.originalIndex < b.originalIndex
    }
}

public final class ClientAssets {
    public let width: Int
    public let height = 4096
    public let reportedVersion: String
    public let fonts:ClassicFonts?
    public let lights:LightAssets?
    public let sounds:SoundAssets?
    public let staticAnimations: StaticAnimations?
    public let animations: AnimationAssets?
    public let skills: [SkillDefinition]
    public let multis: MultiAssets?
    public let gumps: GumpAssets?
    public let radar: RadarMap?
    public var artOverrideCount: Int { patches.count }
    public private(set) var cacheBytes = 0
    public let cacheLimit: Int
    private let map, index, statics, staticIndex, artData: Bytes
    private let verdata: Bytes?
    private let tileData, textureIndex, textureData: Bytes?
    private let hues: HueTable?
    private var patches: [Int: (Int, Int)] = [:]
    private var cache: [Int: (sprite: Sprite, used: UInt64)] = [:]
    private var tick: UInt64 = 0

    public init(directory: URL, cacheLimit: Int = 16 * 1024 * 1024) throws {
        guard cacheLimit >= 0 else { throw AssetError("Negative cache budget") }
        self.cacheLimit = cacheLimit
        var files: [String: URL] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let key = url.lastPathComponent.lowercased()
            guard files[key] == nil else { throw AssetError("Ambiguous filename: \(key)") }
            files[key] = url
        }
        func load(_ name: String) throws -> Bytes {
            guard let url = files[name] else { throw AssetError("Missing \(name) in \(directory.path)") }
            return Bytes(try Data(contentsOf: url, options: .alwaysMapped))
        }
        if files["anim.idx"] != nil, files["anim.mul"] != nil {
            animations = try AnimationAssets(index: load("anim.idx").data, data: load("anim.mul").data)
        } else { animations = nil }
        staticAnimations = files["animdata.mul"].flatMap { try? StaticAnimations(data:Data(contentsOf:$0,options:.alwaysMapped)) }
        fonts = files["fonts.mul"].flatMap { try? ClassicFonts(data:Data(contentsOf:$0,options:.alwaysMapped)) }
        lights = try files["lightidx.mul"] != nil && files["light.mul"] != nil
            ? LightAssets(index:load("lightidx.mul").data,data:load("light.mul").data) : nil
        sounds = try files["soundidx.mul"] != nil && files["sound.mul"] != nil
            ? SoundAssets(index:load("soundidx.mul").data,data:load("sound.mul").data) : nil
        gumps = try files["gumpidx.mul"] != nil && files["gumpart.mul"] != nil
            ? GumpAssets(index: load("gumpidx.mul").data, data: load("gumpart.mul").data,
                         verdata: files["verdata.mul"] == nil ? nil : load("verdata.mul").data) : nil
        skills = try files["skills.idx"] != nil && files["skills.mul"] != nil
            ? SkillAssets.decode(index: load("skills.idx").data, data: load("skills.mul").data) : []
        multis = try files["multi.idx"] != nil && files["multi.mul"] != nil
            ? MultiAssets(index: load("multi.idx").data, data: load("multi.mul").data) : nil
        hues = try files["hues.mul"] == nil ? nil : HueTable(load("hues.mul").data)
        map = try load("map0.mul")
        index = try load("artidx.mul")
        artData = try load("art.mul")
        statics = try load("statics0.mul")
        staticIndex = try load("staidx0.mul")
        tileData = try files["tiledata.mul"] == nil ? nil : load("tiledata.mul")
        textureIndex = try files["texidx.mul"] == nil ? nil : load("texidx.mul")
        textureData = try files["texmaps.mul"] == nil ? nil : load("texmaps.mul")
        if let tileData {
            guard tileData.count >= 512 * 836, (tileData.count - 512 * 836) % 1188 == 0 else {
                throw AssetError("Only legacy 32-bit-flag TILEDATA is supported")
            }
        }
        guard (textureIndex == nil) == (textureData == nil) else {
            throw AssetError("TEXIDX and TEXMAPS must be supplied together")
        }
        guard [6144 * 4096 / 64 * 196, 7168 * 4096 / 64 * 196].contains(map.count) else {
            throw AssetError("Unsupported map0 size: \(map.count)")
        }
        width = map.count / 196 / 512 * 8
        guard staticIndex.count == map.count / 196 * 12, index.count % 12 == 0 else {
            throw AssetError("Invalid map/static or art index size")
        }
        reportedVersion = files["version.txt"].flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        radar = try files["radarcol.mul"] == nil ? nil : RadarMap(map:map.data,
            staticIndex:staticIndex.data,statics:statics.data,colors:load("radarcol.mul").data,width:width,height:height)
        verdata = try files["verdata.mul"] == nil ? nil : load("verdata.mul")
        if let patch = verdata {
            let count = try patch.u32(0)
            try patch.check(4, count * 20)
            for i in 0..<count {
                let p = 4 + i * 20
                let file = try patch.u32(p), block = try patch.u32(p + 4)
                let offset = try patch.u32(p + 8), length = try patch.u32(p + 12)
                try patch.check(offset, length)
                guard ![0, 1, 2].contains(file) else {
                    throw AssetError("Map/static VERDATA patches are not supported yet")
                }
                if file == 4 { patches[block] = (offset, length) }
            }
        }
    }

    public func isNoDraw(graphic:Int) throws -> Bool {
        if graphic == 1 || (0x2198...0x21A2).contains(graphic) || [0x21A4,0x21BC,0x375A].contains(graphic) { return true }
        return try itemFlags(graphic:graphic) & 0x10000 != 0
    }

    public func sprite(_ id: Int) throws -> Sprite? {
        guard id >= 0 else { throw AssetError("Negative art index") }
        tick &+= 1
        if let entry = cache[id] {
            cache[id] = (entry.sprite, tick)
            return entry.sprite
        }
        let raw: Bytes
        if let (offset, length) = patches[id], let verdata {
            raw = try verdata.slice(offset, length)
        } else {
            guard id < index.count / 12 else { throw AssetError("Art index out of range: \(id)") }
            let offset = try index.u32(id * 12), length = try index.u32(id * 12 + 4)
            if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { return nil }
            raw = try artData.slice(offset, length)
        }
        let sprite = try id < 0x4000 ? ArtDecoder.land(raw) : ArtDecoder.item(raw)
        remember(sprite, id: id)
        return sprite
    }

    private func remember(_ sprite: Sprite, id: Int) {
        let cost = sprite.rgba.count
        if cost <= cacheLimit {
            while cacheBytes + cost > cacheLimit, let oldest = cache.min(by: { $0.value.used < $1.value.used }) {
                cacheBytes -= oldest.value.sprite.rgba.count
                cache.removeValue(forKey: oldest.key)
            }
            cache[id] = (sprite, tick)
            cacheBytes += cost
        }
    }

    public func elevation(x: Int, y: Int) throws -> Int {
        // Repeat boundary vertices so the last row/column has a defined quad.
        let x = min(width - 1, max(0, x)), y = min(height - 1, max(0, y))
        let block = (x / 8) * (height / 8) + y / 8
        return try map.i8(block * 196 + 4 + ((y % 8) * 8 + x % 8) * 3 + 2)
    }

    public func terrainTexture(land: Int) throws -> Sprite? {
        guard (0..<0x4000).contains(land), let tileData, let textureIndex, let textureData else { return nil }
        let entry = land / 32 * 836 + 4 + land % 32 * 26
        let texture = try tileData.u16(entry + 4)
        // Wet tiles without an assigned texture retain their original art.
        let flags = try tileData.u32(entry)
        if texture == 0 && flags & 0x80 != 0 { return nil }
        guard texture < textureIndex.count / 12 else { return nil }
        let key = -texture - 1
        tick &+= 1
        if let cached = cache[key] {
            cache[key] = (cached.sprite, tick)
            return cached.sprite
        }
        let offset = try textureIndex.u32(texture * 12), length = try textureIndex.u32(texture * 12 + 4)
        if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { return nil }
        guard length == 8192 || length == 32768 else { throw AssetError("Invalid terrain texture length") }
        let size = length == 8192 ? 64 : 128
        try textureData.check(offset, length)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            ArtDecoder.put(try textureData.u16(offset + i * 2), into: &pixels, at: i)
        }
        let sprite = Sprite(width: size, height: size, rgba: pixels)
        remember(sprite, id: key)
        return sprite
    }

    public func huePalette(_ hue: Int, art: Int? = nil) throws -> HuePalette? {
        var partial = false
        if let art, art >= 0x4000, let tileData {
            let id = art - 0x4000
            let offset = 512 * 836 + id / 32 * 1188 + 4 + id % 32 * 37
            if offset + 37 <= tileData.count { partial = try tileData.u32(offset) & 0x40000 != 0 }
        }
        return try hues?.palette(hue, partial: partial)
    }

    public func predictedStepZ(x: Int, y: Int, fromZ: Int) throws -> Int {
        guard x >= 0, y >= 0, x + 1 < width, y + 1 < height else { return fromZ }
        let corners = try [elevation(x: x, y: y), elevation(x: x+1, y: y),
                           elevation(x: x+1, y: y+1), elevation(x: x, y: y+1)]
        let land = abs(corners[0] - corners[2]) <= abs(corners[1] - corners[3])
            ? (corners[0] + corners[2]) >> 1 : (corners[1] + corners[3]) >> 1
        // Sloped land is reached through its low edge, not by stepping directly
        // onto its average elevation as if it were a vertical static platform.
        var heights = corners.min()! <= fromZ + 8 && land >= fromZ - 20 ? [land] : []
        for tile in try region(x: x, y: y, radius: 0) where tile.isStatic {
            let id = tile.art - 0x4000
            let flags = try itemFlags(graphic: id)
            if flags & 0x200 != 0, flags & 0x40 == 0, let tileData {
                let offset = 512 * 836 + id / 32 * 1188 + 4 + id % 32 * 37
                let height = try tileData.u8(offset + 16)
                let surface = tile.z + (flags & 0x400 != 0 ? height / 2 : height)
                if surface <= fromZ + 8 && surface >= fromZ - 20 { heights.append(surface) }
            }
        }
        // Supporting surfaces cover the terrain beneath them. Choosing the
        // nearest Z incorrectly selected the buried ground under the first stair.
        return heights.max() ?? fromZ
    }
    public func landFlags(graphic:Int) throws -> Int {
        guard (0..<0x4000).contains(graphic), let tileData else { return 0 }
        return try tileData.u32(graphic/32*836+4+graphic%32*26)
    }
    public func itemHeight(graphic:Int) throws -> Int {
        guard (0..<0x4000).contains(graphic), let tileData else { return 0 }
        let offset = 512*836+graphic/32*1188+4+graphic%32*37
        guard offset+37<=tileData.count else { return 0 }
        return try tileData.u8(offset+16)
    }
    public func itemFlags(graphic: Int) throws -> Int {
        guard graphic >= 0, graphic < 0x4000, let tileData else { return 0 }
        let offset = 512 * 836 + graphic / 32 * 1188 + 4 + graphic % 32 * 37
        guard offset + 37 <= tileData.count else { return 0 }
        return try tileData.u32(offset)
    }
    public func lightIndex(graphic:Int) throws -> Int? {
        guard try itemFlags(graphic:graphic) & 0x800000 != 0,let tileData else { return nil }
        if (0x3E02...0x3E0B).contains(graphic) || (0x3914...0x3929).contains(graphic) || graphic == 0xB1D { return 2 }
        let offset = 512*836+graphic/32*1188+4+graphic%32*37
        return try tileData.u8(offset+5)
    }
    public func worldSprite(_ art:Int, at time:TimeInterval) throws -> Sprite? {
        if art >= 0x4000, try itemFlags(graphic:art-0x4000) & 0x01000000 != 0,
           let animated = staticAnimations?.graphic(art-0x4000,at:time), animated != art-0x4000,
           let frame = try sprite(animated+0x4000) { return frame }
        return try sprite(art)
    }
    public func isStackable(graphic: Int) throws -> Bool {
        try itemFlags(graphic: graphic) & 0x00000800 != 0
    }
    public func isDoor(graphic: Int) throws -> Bool {
        guard graphic >= 0, graphic < 0x4000, let tileData else { return false }
        let offset = 512 * 836 + graphic / 32 * 1188 + 4 + graphic % 32 * 37
        guard offset + 37 <= tileData.count else { return false }
        return try tileData.u32(offset) & 0x20000000 != 0
    }
    public func itemName(graphic: Int) throws -> String {
        guard graphic >= 0, graphic < 0x4000, let tileData else { return "Item" }
        let offset = 512 * 836 + graphic / 32 * 1188 + 4 + graphic % 32 * 37
        guard offset + 37 <= tileData.count else { return "Item" }
        let bytes = try (17..<37).map { UInt8(try tileData.u8(offset + $0)) }.prefix { $0 != 0 }
        return String(bytes: bytes, encoding: .ascii).flatMap { $0.isEmpty ? nil : $0 } ?? "Item"
    }
    public func equipmentLayer(graphic: Int) throws -> UInt8? {
        guard (0..<0x4000).contains(graphic), let tileData else { return nil }
        let offset = 512 * 836 + graphic / 32 * 1188 + 4 + graphic % 32 * 37
        guard offset + 37 <= tileData.count else { return nil }
        let layer = UInt8(try tileData.u8(offset + 5))
        return EquipmentRules.isWearable(layer) ? layer : nil
    }
    public func equipmentAnimation(graphic: Int) throws -> Int? {
        guard graphic >= 0, graphic < 0x4000, let tileData else { return nil }
        let offset = 512 * 836 + graphic / 32 * 1188 + 4 + graphic % 32 * 37
        guard offset + 37 <= tileData.count else { return nil }
        let animation = try tileData.u16(offset + 10)
        return animation == 0 ? nil : animation
    }

    func drawPriority(_ tile: WorldTile) throws -> Int {
        if tile.effectAge != nil { return tile.z + 2 } // Above the owning mobile, below higher surfaces.
        if tile.isStatic {
            guard let tileData else { return tile.z }
            let id = tile.art - 0x4000
            let offset = 512 * 836 + id / 32 * 1188 + 4 + id % 32 * 37
            let flags = try tileData.u32(offset), height = try tileData.u8(offset + 16)
            return tile.z - (flags & 1 != 0 ? 1 : 0) + (height > 0 ? 1 : 0)
        }
        let top = tile.z
        let right = try elevation(x: tile.x + 1, y: tile.y)
        let bottom = try elevation(x: tile.x + 1, y: tile.y + 1)
        let left = try elevation(x: tile.x, y: tile.y + 1)
        if top != right || top != bottom || top != left,
           try terrainTexture(land: tile.art) != nil {
            let average = abs(top - bottom) <= abs(left - right) ? (top + bottom) >> 1 : (left + right) >> 1
            return average - 2
        }
        return top - 2
    }

    public func region(x cx: Int, y cy: Int, radius: Int, legacyOrder: Bool = false) throws -> [WorldTile] {
        guard (0..<width).contains(cx), (0..<height).contains(cy), (0...64).contains(radius) else {
            throw AssetError("Region must be on map; radius must be 0...64")
        }
        let x0 = max(0, cx - radius), x1 = min(width, cx + radius + 1)
        let y0 = max(0, cy - radius), y1 = min(height, cy + radius + 1)
        var tiles: [WorldTile] = []
        for bx in (x0 / 8)...((x1 - 1) / 8) {
            for by in (y0 / 8)...((y1 - 1) / 8) {
                let block = bx * (height / 8) + by
                for i in 0..<64 {
                    let x = bx * 8 + i % 8, y = by * 8 + i / 8
                    if x >= x0 && x < x1 && y >= y0 && y < y1 {
                        let p = block * 196 + 4 + i * 3
                        tiles.append(WorldTile(x: x, y: y, z: try map.i8(p + 2), art: try map.u16(p) & 0x3FFF, hue: 0))
                    }
                }
                let offset = try staticIndex.u32(block * 12), length = try staticIndex.u32(block * 12 + 4)
                if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { continue }
                guard length % 7 == 0 else { throw AssetError("Invalid static block length") }
                try statics.check(offset, length)
                for p in stride(from: offset, to: offset + length, by: 7) {
                    let dx = try statics.u8(p + 2), dy = try statics.u8(p + 3)
                    guard dx < 8 && dy < 8 else { throw AssetError("Static outside map block") }
                    let x = bx * 8 + dx, y = by * 8 + dy
                    if x >= x0 && x < x1 && y >= y0 && y < y1 {
                        tiles.append(WorldTile(x: x, y: y, z: try statics.i8(p + 4),
                                               art: try statics.u16(p) + 0x4000, hue: try statics.u16(p + 5)))
                    }
                }
            }
        }
        if !legacyOrder {
            let entries = try tiles.enumerated().map {
                DrawEntry(tile: $0.element, priority: try drawPriority($0.element), originalIndex: $0.offset)
            }
            return entries.sorted(by: DrawEntry.precedes).map(\.tile)
        }
        // Preserve the initial host decoder's ordering only for regression comparisons.
        return tiles.enumerated().sorted { a, b in
            let l = a.element, r = b.element
            if l.x + l.y != r.x + r.y { return l.x + l.y < r.x + r.y }
            if l.z != r.z { return l.z < r.z }
            if l.isStatic != r.isStatic { return !l.isStatic }
            if l.x != r.x { return l.x < r.x }
            return a.offset < b.offset
        }.map(\.element)
    }
}
