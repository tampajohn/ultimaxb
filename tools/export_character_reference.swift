import AppKit
import UOCore

/// Export a local reference sheet from installed MUL assets; never modifies the assets.
@main struct ExportCharacterReference {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let cellWidth = 96, cellHeight = 128, scale = 4
        let width = cellWidth*2*scale, height = cellHeight*2*scale
        var rgba = [UInt8](repeating:0,count:width*height*4)
        let clothing = [(0x1517,UInt8(5),1109),(0x152E,UInt8(4),1837),(0x170B,UInt8(3),0),(0x203B,UInt8(11),1109)]
        for (index,direction) in [UInt8(3),5,7,1].enumerated() {
            let equipment = clothing.enumerated().map { EquippedItem(serial:UInt32($0.offset+2),graphic:$0.element.0,layer:$0.element.1,owner:1,hue:$0.element.2) }
            var layers:[(AnimationFrame,Int,Int?)] = [(try assets.animations!.frame(body:400,direction:direction,action:4)!,1002,nil)]
            for item in EquipmentOrder.sorted(equipment,direction:direction) {
                if let body = try assets.equipmentAnimation(graphic:item.graphic),let frame = try assets.animations?.frame(body:body,direction:direction,action:4) {
                    layers.append((frame,item.hue,item.graphic+0x4000))
                }
            }
            for (frame,hue,art) in layers {
                let sprite = frame.sprite
                let palette = try assets.huePalette(hue,art:art)
                let ox = 48-(frame.mirrored ? sprite.width-frame.centerX : frame.centerX)
                let oy = 108-sprite.height-frame.centerY
                for y in 0..<sprite.height {
                    for x in 0..<sprite.width {
                        let source = (y*sprite.width+(frame.mirrored ? sprite.width-1-x : x))*4
                        guard sprite.rgba[source+3] != 0 else { continue }
                        let color = palette?.color(red:sprite.rgba[source],green:sprite.rgba[source+1],blue:sprite.rgba[source+2]) ?? (sprite.rgba[source],sprite.rgba[source+1],sprite.rgba[source+2])
                        let px = ox+x, py = oy+y
                        guard px>=0,py>=0,px<cellWidth,py<cellHeight else { continue }
                        for dy in 0..<scale { for dx in 0..<scale {
                            let target = (((index/2*cellHeight+py)*scale+dy)*width+(index%2*cellWidth+px)*scale+dx)*4
                            rgba[target] = color.0; rgba[target+1] = color.1; rgba[target+2] = color.2; rgba[target+3] = 255
                        } }
                    }
                }
            }
        }
        let provider = CGDataProvider(data:Data(rgba) as CFData)!
        let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let path = "build/visual-upgrade/character-original-reference.png"
        try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
        print(path)
    }
}
