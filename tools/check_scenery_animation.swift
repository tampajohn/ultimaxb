import Foundation
import UOCore
@main struct Check {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let packet = Data([0x1A,0,14,0x40,0,0,1,0x0D,0xE3,0,100,0,100,0])
        let item = try GroundItem.decode(packet)
        let camera = WorldCamera(x:100,y:100)
        var frames = [[UInt8]]()
        for time in [0.0,0.17,0.33] {
            let sprite = try assets.worldSprite(0x4DE3,at:time)!
            frames.append(sprite.rgba)
            let opaque = stride(from:3,to:sprite.rgba.count,by:4).first { sprite.rgba[$0] != 0 }!/4
            let x = 480-sprite.width/2+opaque%sprite.width
            let y = 360+44-sprite.height+opaque/sprite.width
            let hit = try WorldHitTest.groundItem(assets:assets,animationTime:time,items:[item],camera:camera,screenX:Double(x),screenY:Double(y))
            precondition(hit?.serial == item.serial && hit?.graphic == item.graphic)
        }
        precondition(frames[0] != frames[1] && frames[1] != frames[2])
        var world = WorldState()
        _ = try world.apply(packet)
        let tile = world.groundTiles[0]
        let first = try WorldRenderer.render(assets,x:100,y:100,groundItems:[tile],animationTime:0)
        let next = try WorldRenderer.render(assets,x:100,y:100,groundItems:[tile],animationTime:0.17)
        precondition(first.rgba != next.rgba)
        precondition(assets.cacheBytes <= assets.cacheLimit)
        print("Installed fire frames animate, hit tests retain original identity, world frames differ, cache stays bounded")
    }
}
