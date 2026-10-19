import Foundation

/// The 0x2006 world item stores its creature body in the amount field.
/// Corpses use the final frame of the body's classic death animation.
public enum CorpseArt {
    public static func deathAction(body:Int,alternate:Bool = false) -> Int {
        body < 200 ? (alternate ? 3 : 2) : (body < 400 ? (alternate ? 12 : 8) : (alternate ? 22 : 21))
    }
    public static func frame(body:Int,direction:UInt8,assets:ClientAssets,hue:Int = 0,equipment:[EquippedItem] = []) throws -> AnimationFrame? {
        let action = deathAction(body:body,alternate:direction & 0x80 != 0)
        guard let count = try assets.animations?.frameCount(body:body,direction:direction,action:action) else { return nil }
        guard let base = try assets.animations?.frame(body:body,direction:direction,action:action,frame:count-1) else { return nil }
        var layers:[(AnimationFrame,HuePalette?)] = [(base,try assets.huePalette(hue))]
        if body == 400 || body == 401 {
            for item in EquipmentOrder.sorted(equipment,direction:direction) {
                guard let animation = try assets.equipmentAnimation(graphic:item.graphic),
                      let frames = try assets.animations?.frameCount(body:animation,direction:direction,action:action),
                      let frame = try assets.animations?.frame(body:animation,direction:direction,action:action,frame:frames-1) else { continue }
                layers.append((frame,try assets.huePalette(item.hue,art:item.graphic+0x4000)))
            }
        }
        if layers.count == 1 && layers[0].1 == nil { return base }
        func origin(_ frame:AnimationFrame)->(Int,Int) {
            (-(frame.mirrored ? frame.sprite.width-frame.centerX : frame.centerX),22-frame.sprite.height-frame.centerY)
        }
        let left = layers.map { origin($0.0).0 }.min()!, top = layers.map { origin($0.0).1 }.min()!
        let right = layers.map { origin($0.0).0+$0.0.sprite.width }.max()!
        let bottom = layers.map { origin($0.0).1+$0.0.sprite.height }.max()!
        let width = right-left, height = bottom-top
        guard width > 0,height > 0,width <= 2048,height <= 2048 else { throw AssetError("Oversized corpse composite") }
        var rgba = [UInt8](repeating:0,count:width*height*4)
        for (frame,palette) in layers {
            let sprite = frame.sprite, (x,y) = origin(frame)
            for yy in 0..<sprite.height {
                for xx in 0..<sprite.width {
                    let source = (yy*sprite.width+(frame.mirrored ? sprite.width-1-xx : xx))*4
                    guard sprite.rgba[source+3] != 0 else { continue }
                    let color = palette?.color(red:sprite.rgba[source],green:sprite.rgba[source+1],blue:sprite.rgba[source+2])
                        ?? (sprite.rgba[source],sprite.rgba[source+1],sprite.rgba[source+2])
                    let dest = ((y-top+yy)*width+x-left+xx)*4
                    rgba[dest] = color.0; rgba[dest+1] = color.1; rgba[dest+2] = color.2; rgba[dest+3] = 255
                }
            }
        }
        return AnimationFrame(sprite:Sprite(width:width,height:height,rgba:rgba),centerX:-left,centerY:22-bottom,mirrored:false)
    }
}
