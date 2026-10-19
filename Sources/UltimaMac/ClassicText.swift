import AppKit
import UOCore

/// Small labels drawn at native bitmap resolution, with a one-pixel dark edge.
@MainActor final class ClassicText {
    private let fonts:ClassicFonts?
    private var glyphs:[UInt32:(NSImage,NSImage,NSSize,Int)] = [:]
    private let outlined:Bool
    private let fontID:Int
    private let color:(UInt8,UInt8,UInt8)
    init(_ fonts:ClassicFonts?,font:Int = 9,color:(UInt8,UInt8,UInt8) = (230,215,170),outlined:Bool = true) { self.fonts=fonts; fontID=font; self.color=color; self.outlined=outlined }
    func lines(_ value:String,width:CGFloat)->[String] {
        var result:[String]=[]
        for paragraph in value.components(separatedBy:"\n") {
            var line=""
            for word in paragraph.components(separatedBy:" ") {
                let candidate=line.isEmpty ? word : line+" "+word
                if !line.isEmpty && size(candidate).width>width { result.append(line); line="" }
                for character in (line.isEmpty ? word : " "+word) {
                    if !line.isEmpty && size(line+String(character)).width>width { result.append(line); line="" }
                    line.append(character)
                }
            }
            result.append(line)
        }
        return result
    }
    private func glyph(_ scalar:Unicode.Scalar)->(NSImage,NSImage,NSSize,Int)? {
        if let value=glyphs[scalar.value] { return value }
        guard let fonts,let glyph=try? fonts.glyph(scalar,font:max(0,min(fontID,fonts.count-1))),glyph.sprite.width>0,glyph.sprite.height>0 else { return nil }
        let sprite=glyph.sprite
        func image(_ color:(UInt8,UInt8,UInt8),preserveEdge:Bool = false)->NSImage {
            var pixels=sprite.rgba
            for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3] != 0 {
                let edge=preserveEdge && (fontID == 0 || fontID == 3) && max(pixels[i],pixels[i+1],pixels[i+2])<64
                pixels[i]=edge ? 20 : color.0; pixels[i+1]=edge ? 15 : color.1; pixels[i+2]=edge ? 10 : color.2
            }
            let provider=CGDataProvider(data:Data(pixels) as CFData)!
            let cg=CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
        }
        let value=(image(color,preserveEdge:true),image((20,15,10)),NSSize(width:sprite.width,height:sprite.height),glyph.offsetY)
        glyphs[scalar.value]=value
        return value
    }
    func size(_ text:String)->NSSize {
        var width:CGFloat=0,height:CGFloat=0
        for scalar in text.unicodeScalars {
            if let g=glyph(scalar) { width += g.2.width; height=max(height,g.2.height+CGFloat(g.3)) }
            else { width += 4 }
        }
        return NSSize(width:width,height:height)
    }
    func draw(_ text:String,at point:NSPoint) {
        NSGraphicsContext.current?.imageInterpolation = .none
        var x=point.x
        for scalar in text.unicodeScalars {
            guard let g=glyph(scalar) else { x += 4; continue }
            let rect=NSRect(x:x.rounded(),y:(point.y+CGFloat(g.3)).rounded(),width:g.2.width,height:g.2.height)
            for (dx,dy) in (!outlined || fontID == 0 || fontID == 3 ? [] : [(-1,0),(1,0),(0,-1),(0,1)]) {
                g.1.draw(in:rect.offsetBy(dx:CGFloat(dx),dy:CGFloat(dy)),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
            g.0.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            x += g.2.width
        }
    }
}
