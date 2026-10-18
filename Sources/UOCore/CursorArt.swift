import Foundation

/// Marker decoding and IDs follow ClassicUO Art.cs/GameCursor.cs; LICENSES/ClassicUO.txt.
public struct CursorArt {
    public let sprite: Sprite
    public let hotX: Int, hotY: Int
    public init(sprite: Sprite) {
        var pixels = sprite.rgba, hx = 0, hy = 0
        for y in 0..<sprite.height {
            for x in 0..<sprite.width {
                let p = (y*sprite.width+x)*4
                guard pixels[p+3] != 0 else { continue }
                let green = pixels[p] == 0 && pixels[p+1] == 255 && pixels[p+2] == 0
                if green { if x == 0 { hy = y }; if y == 0 { hx = x } }
                if green || (pixels[p] == 0 && pixels[p+1] == 0 && pixels[p+2] == 0) || x == 0 || y == 0 || x == sprite.width-1 || y == sprite.height-1 {
                    pixels[p+3] = 0
                }
            }
        }
        self.sprite = Sprite(width: sprite.width, height: sprite.height, rgba: pixels)
        hotX = hx; hotY = hy
    }
    public static func graphic(war: Bool, targeting: Bool, pickup: Bool, direction: Int? = nil) -> Int {
        let base = war ? 0x2053 : 0x206A
        return base + (targeting ? 12 : pickup ? 8 : direction.map { $0 & 7 } ?? 9)
    }
}
