import Foundation

struct TerrainVertex {
    let x: Double, y: Double, u: Double, v: Double
}

enum TerrainRasterizer {
    // Affine textured triangles with pixel-center sampling. Adjacent tiles use
    // exactly the same world vertices, so their edges meet at changing elevations.
    static func triangle(_ a: TerrainVertex, _ b: TerrainVertex, _ c: TerrainVertex,
                         texture: Sprite, width: Int, height: Int, pixels: inout [UInt8]) {
        let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        if abs(denominator) < 0.000001 { return }
        let x0 = max(0, Int(floor(min(a.x, b.x, c.x))))
        let x1 = min(width - 1, Int(ceil(max(a.x, b.x, c.x))))
        let y0 = max(0, Int(floor(min(a.y, b.y, c.y))))
        let y1 = min(height - 1, Int(ceil(max(a.y, b.y, c.y))))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let wa = ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / denominator
                let wb = ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / denominator
                let wc = 1 - wa - wb
                guard wa >= -1e-9, wb >= -1e-9, wc >= -1e-9 else { continue }
                let u = min(texture.width - 1, max(0, Int((wa * a.u + wb * b.u + wc * c.u) * Double(texture.width))))
                let v = min(texture.height - 1, max(0, Int((wa * a.v + wb * b.v + wc * c.v) * Double(texture.height))))
                let src = (v * texture.width + u) * 4, dst = (y * width + x) * 4
                pixels[dst] = texture.rgba[src]
                pixels[dst + 1] = texture.rgba[src + 1]
                pixels[dst + 2] = texture.rgba[src + 2]
            }
        }
    }

    static func draw(texture: Sprite, screenX: Int, screenY: Int, z: [Int],
                     width: Int, height: Int, pixels: inout [UInt8]) {
        let top = TerrainVertex(x: Double(screenX), y: Double(screenY - z[0] * 4), u: 0, v: 0)
        let right = TerrainVertex(x: Double(screenX + 22), y: Double(screenY + 22 - z[1] * 4), u: 1, v: 0)
        let bottom = TerrainVertex(x: Double(screenX), y: Double(screenY + 44 - z[2] * 4), u: 1, v: 1)
        let left = TerrainVertex(x: Double(screenX - 22), y: Double(screenY + 22 - z[3] * 4), u: 0, v: 1)
        if abs(z[0] - z[2]) <= abs(z[1] - z[3]) {
            triangle(top, right, bottom, texture: texture, width: width, height: height, pixels: &pixels)
            triangle(top, bottom, left, texture: texture, width: width, height: height, pixels: &pixels)
        } else {
            triangle(top, right, left, texture: texture, width: width, height: height, pixels: &pixels)
            triangle(right, bottom, left, texture: texture, width: width, height: height, pixels: &pixels)
        }
    }
}
