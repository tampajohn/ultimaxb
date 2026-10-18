import Foundation
import UOCore
@main struct Check {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        for body in [1,200,400] {
            for direction in UInt8(0)...7 {
                let packet = Data([0x1A,0,17,0xC0,0,0,1,0x20,0x06,UInt8(body>>8),UInt8(body&255),0x80,100,0,100,direction,0])
                let item = try GroundItem.decode(packet)
                guard let frame = try CorpseArt.frame(body:body,direction:direction,assets:assets) else { fatalError("Missing death frame") }
                let sprite = frame.sprite
                let pixel = stride(from:3,to:sprite.rgba.count,by:4).first { sprite.rgba[$0] != 0 }!/4
                let sourceX = pixel%sprite.width
                let x = 480-(frame.mirrored ? sprite.width-frame.centerX : frame.centerX)+(frame.mirrored ? sprite.width-1-sourceX : sourceX)
                let y = 360+22-sprite.height-frame.centerY+pixel/sprite.width
                let hit = try WorldHitTest.groundItem(assets:assets,items:[item],camera:WorldCamera(x:100,y:100),screenX:Double(x),screenY:Double(y))
                precondition(hit?.serial == item.serial)
                var world = WorldState(); _ = try world.apply(packet)
                let output = try WorldRenderer.render(assets,x:100,y:100,groundItems:world.groundTiles)
                precondition(output.rgba.count == 960*720*4)
            }
        }
        let shirt = EquippedItem(serial:0x40000002,graphic:0x1517,layer:5,owner:0x40000001,hue:33)
        for direction in UInt8(0)...7 {
            let bare = try CorpseArt.frame(body:400,direction:direction,assets:assets)!
            let dressed = try CorpseArt.frame(body:400,direction:direction,assets:assets,equipment:[shirt])!
            precondition(bare.sprite.rgba != dressed.sprite.rgba)
            let packet = Data([0x1A,0,17,0xC0,0,0,1,0x20,0x06,1,0x90,0x80,100,0,100,direction,0])
            var world = WorldState(); _ = try world.apply(packet)
            _ = try world.apply(Data([0x89,0,13,0x40,0,0,1,5,0x40,0,0,2,0]))
            _ = try world.apply(Data([0x25,0x40,0,0,2,0x15,0x17,0,0,1,0,10,0,10,0x40,0,0,1,0,33]))
            let sprite = dressed.sprite
            let pixel = stride(from:3,to:sprite.rgba.count,by:4).first { sprite.rgba[$0] != 0 }!/4
            let x = 480-dressed.centerX+pixel%sprite.width
            let y = 360+22-sprite.height-dressed.centerY+pixel/sprite.width
            let hit = try WorldHitTest.groundItem(assets:assets,items:world.groundObjects,camera:WorldCamera(x:100,y:100),screenX:Double(x),screenY:Double(y))
            precondition(hit?.serial == 0x40000001)
            let output = try WorldRenderer.render(assets,x:100,y:100,groundItems:world.groundTiles)
            precondition(output.rgba.count == 960*720*4)
        }
        print("Monster, animal and human corpse frames and hued clothing render and select in all eight directions")
    }
}
