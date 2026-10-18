import Foundation

/// Legacy MULTI.MUL components: graphic, signed XYZ offsets, visibility flags.
public final class MultiAssets {
    private let index: Bytes, data: Bytes
    public init(index: Data, data: Data) throws {
        guard index.count % 12 == 0 else { throw AssetError("Invalid multi index") }
        self.index = Bytes(index); self.data = Bytes(data)
    }
    public func tiles(id: Int, x: Int, y: Int, z: Int, hue: Int = 0) throws -> [WorldTile] {
        guard id >= 0, id < index.count/12 else { return [] }
        let offset = try index.u32(id*12), length = try index.u32(id*12+4)
        guard offset != 0xFFFFFFFF, length != 0, length != 0xFFFFFFFF else { return [] }
        guard length % 12 == 0, length/12 <= 65536 else { throw AssetError("Invalid multi length") }
        let raw = try data.slice(offset, length)
        func signed(_ p: Int) throws -> Int { Int(Int16(bitPattern: UInt16(try raw.u16(p)))) }
        var tiles: [WorldTile] = []
        for p in stride(from: 0, to: length, by: 12) {
            let graphic = try raw.u16(p)
            let visible = try raw.u32(p+8) != 0
            // ClassicUO Item.LoadMulti uses the first invisible component as
            // the root item's display graphic (e.g. a boat mast). Other invisible
            // components are separate server items such as hatches and planks.
            if !visible {
                if p == 0 && graphic > 2 && graphic < 0x4000 {
                    tiles.append(WorldTile(x:x,y:y,z:z,art:graphic+0x4000,hue:hue))
                }
                continue
            }
            guard graphic < 0x4000 else { throw AssetError("Invalid multi graphic") }
            tiles.append(try WorldTile(x: x+signed(p+2), y: y+signed(p+4), z: z+signed(p+6), art: graphic+0x4000, hue: hue))
        }
        return tiles
    }
}
