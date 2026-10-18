import Foundation

/// Shared image placement for selecting and highlighting a world item.
public struct WorldItemAppearance {
    public let sprite:Sprite
    public let offsetX:Int, offsetY:Int
    public let mirrored:Bool
    public static func load(_ item:GroundItem,assets:ClientAssets,at time:TimeInterval = 0) throws -> WorldItemAppearance? {
        if item.graphic == 0x2006,
           let frame = try CorpseArt.frame(body:item.amount,direction:item.direction,assets:assets,hue:item.hue,equipment:item.corpseEquipment) {
            return WorldItemAppearance(sprite:frame.sprite,
                offsetX:-(frame.mirrored ? frame.sprite.width-frame.centerX : frame.centerX),
                offsetY:22-frame.sprite.height-frame.centerY,mirrored:frame.mirrored)
        }
        guard let sprite = try assets.worldSprite(item.graphic+0x4000,at:time) else { return nil }
        return WorldItemAppearance(sprite:sprite,offsetX:-(sprite.width/2),offsetY:44-sprite.height,mirrored:false)
    }
    public func opaque(x:Int,y:Int)->Bool {
        guard x >= 0,y >= 0,x < sprite.width,y < sprite.height else { return false }
        let sourceX = mirrored ? sprite.width-1-x : x
        return sprite.rgba[(y*sprite.width+sourceX)*4+3] != 0
    }
}
