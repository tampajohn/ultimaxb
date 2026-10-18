import Foundation
import UOCore
@main struct Check {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let packet = Data([0x70,2,0,0,0,0,0,0,0,0,0x37,0x6A,
            0x09,0xBD,0x01,0xE2,15,0,0,0,0,0,5,40,0,0,1,0])
        var effects = StationaryEffects()
        effects.append(try GraphicEffect.decode(packet),at:0)
        let base = try WorldRenderer.render(assets,x:2493,y:482)
        let first = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0,mobiles:[],items:[]))
        let later = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0.2,mobiles:[],items:[]))
        precondition(first.missingCount == 0 && later.missingCount == 0)
        precondition(first.rgba != base.rgba && later.rgba != first.rgba, "Effect must render and animate")
        let expired = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:2,mobiles:[],items:[]))
        precondition(expired.rgba == base.rgba)
        print("Original spell art renders, advances frames, and disappears at server-specified expiry")
    }
}
