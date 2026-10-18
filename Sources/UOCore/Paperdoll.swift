import Foundation

/// Original paperdoll gumps share an origin, including transparent padding.
/// ClassicUO's paperdoll layout and classic layer order: LICENSES/ClassicUO.txt.
public enum Paperdoll {
    public struct Layer {
        public let sprite: Sprite
        public let item: EquippedItem?
    }
    public static func layers(assets: ClientAssets, body: Int, hue: Int,
                              owner: UInt32, equipment: [EquippedItem]) throws -> [Layer] {
        guard let gumps = assets.gumps else { return [] }
        let female = body == 401 || body == 403
        var result: [Layer] = []
        func append(_ sprite: Sprite, hue: Int, art: Int?, item: EquippedItem?) throws {
            var pixels = sprite.rgba
            if let palette = try assets.huePalette(hue, art: art) {
                for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i+3] != 0 {
                    let c = palette.color(red: pixels[i], green: pixels[i+1], blue: pixels[i+2])
                    pixels[i] = c.0; pixels[i+1] = c.1; pixels[i+2] = c.2
                }
            }
            result.append(Layer(sprite: Sprite(width: sprite.width, height: sprite.height, rgba: pixels), item: item))
        }
        if let sprite = try gumps.sprite(female ? 13 : 12) {
            try append(sprite, hue: hue | 0x8000, art: nil, item: nil)
        }
        let order: [UInt8] = [20,5,4,3,24,19,13,17,8,14,7,23,22,12,10,11,16,18,6,1,2,21]
        let worn = equipment.filter { $0.owner == owner && order.contains($0.layer) }.sorted {
            order.firstIndex(of: $0.layer)! < order.firstIndex(of: $1.layer)!
        }
        for item in worn {
            guard let animation = try assets.equipmentAnimation(graphic: item.graphic) else { continue }
            let offset = female && item.layer != 21 ? 60000 : 50000
            if let sprite = try gumps.sprite(offset + animation) ?? gumps.sprite((offset == 50000 ? 60000 : 50000) + animation) {
                try append(sprite, hue: item.hue & 0x3FFF, art: item.graphic + 0x4000, item: item)
            }
        }
        return result
    }
}
