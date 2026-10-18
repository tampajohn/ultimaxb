import Foundation
import UOCore
@main struct Check {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let packet = Data([0x70,2,0,0,0,0,0,0,0,0,0x37,0x6A,
            0x09,0xBD,0x01,0xE2,15,0,0,0,0,0,5,40,0,0,1,0])
        var effects = WorldEffects()
        effects.append(try GraphicEffect.decode(packet),at:0)
        let base = try WorldRenderer.render(assets,x:2493,y:482)
        let first = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0,mobiles:[],items:[]))
        let later = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0.2,mobiles:[],items:[]))
        precondition(first.missingCount == 0 && later.missingCount == 0)
        precondition(first.rgba != base.rgba && later.rgba != first.rgba, "Effect must render and animate")
        let expired = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:2,mobiles:[],items:[]))
        precondition(expired.rgba == base.rgba)
        let mobile = WorldMobile(serial:1,body:400,x:2493,y:482,z:15)
        var lightningPacket = packet
        lightningPacket[1] = 1; lightningPacket[5] = 1; lightningPacket[10] = 0; lightningPacket[11] = 0
        effects.append(try GraphicEffect.decode(lightningPacket),at:3)
        let lightning = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:3,mobiles:[mobile],items:[]),mobiles:[mobile])
        let lightningNext = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:3.11,mobiles:[mobile],items:[]),mobiles:[mobile])
        precondition(lightning.missingCount == 0 && lightningNext.missingCount == 0)
        precondition(lightning.rgba != lightningNext.rgba)
        effects = WorldEffects()
        var missile = packet
        missile[1] = 0; missile[10] = 0x36; missile[11] = 0xD4
        missile[17] = 0x09; missile[18] = 0xC2; missile[19] = 0x01; missile[20] = 0xE2; missile[21] = 15
        missile[22] = 1; missile[26] = 0; missile[27] = 1
        effects.append(try GraphicEffect.decode(missile),at:0)
        let flight = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0.1,mobiles:[],items:[]))
        let laterFlight = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0.2,mobiles:[],items:[]))
        let impact = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:1,mobiles:[],items:[]))
        precondition(flight.missingCount == 0 && laterFlight.missingCount == 0 && impact.missingCount == 0)
        precondition(flight.rgba != base.rgba && flight.rgba != laterFlight.rgba && impact.rgba != base.rgba)
        try flight.writeBMP(to:URL(fileURLWithPath:"build/spell-missile.bmp"))
        try lightning.writeBMP(to:URL(fileURLWithPath:"build/spell-lightning.bmp"))
        print("Original spell aura, lightning, rotating missile and impact art render and animate without missing sprites")
    }
}
