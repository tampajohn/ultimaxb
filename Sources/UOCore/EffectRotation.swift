import Foundation

/// Nearest-neighbor rotation of classic projectile art about its top-left anchor.
/// The returned origin preserves that anchor after expanding the pixel bounds.
enum EffectRotation {
    static func rotate(_ source:Sprite, radians:Double) -> (sprite:Sprite,x:Int,y:Int) {
        guard radians.isFinite else { return (source,0,0) }
        let c = cos(radians), s = sin(radians)
        let corners = [(0.0,0.0),(Double(source.width),0.0),(0.0,Double(source.height)),(Double(source.width),Double(source.height))]
            .map { (x:$0.0*c-$0.1*s,y:$0.0*s+$0.1*c) }
        let left = Int(floor(corners.map(\.x).min()!)), top = Int(floor(corners.map(\.y).min()!))
        let width = Int(ceil(corners.map(\.x).max()!))-left
        let height = Int(ceil(corners.map(\.y).max()!))-top
        guard width > 0, height > 0, width <= 2048, height <= 2048 else { return (source,0,0) }
        var pixels = [UInt8](repeating:0,count:width*height*4)
        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x+left)+0.5, py = Double(y+top)+0.5
                let sx = Int(floor(px*c+py*s)), sy = Int(floor(-px*s+py*c))
                guard sx >= 0, sy >= 0, sx < source.width, sy < source.height else { continue }
                let from = (sy*source.width+sx)*4, to = (y*width+x)*4
                for channel in 0..<4 { pixels[to+channel] = source.rgba[from+channel] }
            }
        }
        return (Sprite(width:width,height:height,rgba:pixels),left,top)
    }
}
