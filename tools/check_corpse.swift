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
        print("Monster, animal and human corpse frames render and select in all eight directions")
    }
}
