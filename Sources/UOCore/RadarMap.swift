import Foundation

/// North-up map pixels from the client's map/statics and RADARCOL RGB555 palette.
public final class RadarMap {
    public let width:Int, height:Int
    private let map:Bytes, staticIndex:Bytes, statics:Bytes, colors:Bytes
    public init(map:Data, staticIndex:Data, statics:Data, colors:Data, width:Int, height:Int) throws {
        guard width > 0, height > 0, width <= 7168, height <= 4096,
              width % 8 == 0, height % 8 == 0,
              map.count == width/8 * (height/8) * 196,
              staticIndex.count == width/8 * (height/8) * 12, colors.count >= 0x8000 else {
            throw AssetError("Invalid radar map assets")
        }
        self.width = width; self.height = height
        self.map = Bytes(map); self.staticIndex = Bytes(staticIndex)
        self.statics = Bytes(statics); self.colors = Bytes(colors)
    }
    public func render(x:Int,y:Int,pixelWidth:Int,pixelHeight:Int,step:Int) throws -> Sprite {
        guard (1...1024).contains(pixelWidth), (1...1024).contains(pixelHeight), (1...64).contains(step),
              (-7168...14336).contains(x), (-4096...8192).contains(y) else { throw AssetError("Invalid radar viewport") }
        var pixels = [UInt8](repeating:0,count:pixelWidth*pixelHeight*4)
        var heights = [Int](repeating:Int.min,count:pixelWidth*pixelHeight)
        func color(_ art:Int,at pixel:Int) throws {
            guard art >= 0, art*2+2 <= colors.count else { return }
            ArtDecoder.put(try colors.u16(art*2),into:&pixels,at:pixel)
        }
        for py in 0..<pixelHeight { for px in 0..<pixelWidth {
            let wx = x+px*step, wy = y+py*step
            let pixel = py*pixelWidth+px
            pixels[pixel*4+3] = 255
            guard (0..<width).contains(wx), (0..<height).contains(wy) else { continue }
            let block = (wx/8)*(height/8)+wy/8
            let offset = block*196+4+(wy%8*8+wx%8)*3
            heights[pixel] = try map.i8(offset+2)
            try color(map.u16(offset)&0x3FFF,at:pixel)
        } }
        // Local views include building footprints and vegetation. The world
        // overview samples terrain only, avoiding a scan of the entire statics file.
        if step == 1 {
            let x0 = max(0,x), x1 = min(width,x+pixelWidth)
            let y0 = max(0,y), y1 = min(height,y+pixelHeight)
            if x0 < x1, y0 < y1 {
                for bx in (x0/8)...((x1-1)/8) { for by in (y0/8)...((y1-1)/8) {
                    let block = bx*(height/8)+by
                    let offset = try staticIndex.u32(block*12), length = try staticIndex.u32(block*12+4)
                    if offset == 0xFFFFFFFF || length == 0 || length == 0xFFFFFFFF { continue }
                    guard length % 7 == 0 else { throw AssetError("Invalid radar statics block") }
                    try statics.check(offset,length)
                    for p in stride(from:offset,to:offset+length,by:7) {
                        let dx = try statics.u8(p+2), dy = try statics.u8(p+3)
                        guard dx < 8, dy < 8 else { throw AssetError("Radar static outside block") }
                        let wx = bx*8+dx, wy = by*8+dy
                        guard wx >= x0, wx < x1, wy >= y0, wy < y1 else { continue }
                        let art = try statics.u16(p), z = try statics.i8(p+4)
                        let pixel = (wy-y)*pixelWidth+wx-x
                        guard art > 1, z >= heights[pixel] else { continue }
                        try color(art+0x4000,at:pixel); heights[pixel] = z
                    }
                } }
            }
        }
        return Sprite(width:pixelWidth,height:pixelHeight,rgba:pixels)
    }
}

public enum RadarWidget {
    /// The original radar gump reserves RGB555 0x0421 (8,8,8) for map pixels.
    /// Match that mask exactly, preserving its rounded frame and transparent corners.
    public static func compose(frame:Sprite,terrain:Sprite,centerX:Int,centerY:Int) throws -> Sprite {
        guard frame.rgba.count == frame.width*frame.height*4,
              terrain.rgba.count == terrain.width*terrain.height*4 else { throw AssetError("Invalid radar pixels") }
        var pixels = frame.rgba
        for y in 0..<frame.height { for x in 0..<frame.width {
            let p = (y*frame.width+x)*4
            guard pixels[p] == 8, pixels[p+1] == 8, pixels[p+2] == 8, pixels[p+3] == 255 else { continue }
            let dx = x-frame.width/2, dy = y-frame.height/2
            let tx = centerX+Int(floor(Double(dx+dy)/2)), ty = centerY+Int(floor(Double(dy-dx)/2))
            guard (0..<terrain.width).contains(tx), (0..<terrain.height).contains(ty) else { continue }
            let t = (ty*terrain.width+tx)*4
            pixels[p] = terrain.rgba[t]; pixels[p+1] = terrain.rgba[t+1]; pixels[p+2] = terrain.rgba[t+2]
        } }
        return Sprite(width:frame.width,height:frame.height,rgba:pixels)
    }
}
