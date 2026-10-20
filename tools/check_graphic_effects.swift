import AppKit
import UOCore
@main struct Check {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let packet = Data([0x70,2,0,0,0,0,0,0,0,0,0x37,0x6A,
            0x09,0xBD,0x01,0xE2,15,0,0,0,0,0,5,40,0,0,1,0])
        let suite = "com.ultimaxb.effects.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(false,forKey:"rememberPassword")
        let connection = GameConnection()
        let login = LoginOverlay(assets:assets,loginDefaults:defaults,connection:connection)
        var received:[GraphicEffect] = []
        login.onGraphicEffect = { received.append($0) }
        var coloredPacket = packet; coloredPacket[0] = 0xC0
        coloredPacket += Data([0,0,0,33,0,0,0,2])
        var particlePacket = coloredPacket; particlePacket[0] = 0xC7
        particlePacket += Data(repeating:0,count:13)
        for byte in packet+coloredPacket+particlePacket { connection.onEvent?(.gameData(Data([byte]))) }
        precondition(received.count == 3 && received[1].hue == 33 && received[2].blendMode == 2)
        var fades:[Int] = []
        login.onScreenFade = { fades.append($0) }
        var fadePacket = packet; fadePacket[1] = 4; fadePacket[10] = 0; fadePacket[11] = 2
        connection.onEvent?(.gameData(fadePacket))
        fadePacket[11] = 99
        connection.onEvent?(.gameData(fadePacket))
        coloredPacket[1] = 4
        connection.onEvent?(.gameData(coloredPacket))
        precondition(fades == [2,4] && received.count == 3,"Only legacy screen effects own the overlay")
        var effects = WorldEffects()
        effects.append(try GraphicEffect.decode(packet),at:0)
        let base = try WorldRenderer.render(assets,x:2493,y:482)
        let first = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0,mobiles:[],items:[]))
        let later = try WorldRenderer.render(assets,x:2493,y:482,groundItems:effects.tiles(at:0.2,mobiles:[],items:[]))
        precondition(first.missingCount == 0 && later.missingCount == 0)
        precondition(first.rgba != base.rgba && later.rgba != first.rgba, "Effect must render and animate")
        var extended = packet; extended[0] = 0xC0
        extended += Data([0,0,0,33,0,0,0,0])
        var coloredEffects = WorldEffects()
        coloredEffects.append(try GraphicEffect.decode(extended),at:0)
        let colored = try WorldRenderer.render(assets,x:2493,y:482,groundItems:coloredEffects.tiles(at:0,mobiles:[],items:[]))
        precondition(colored.missingCount == 0 && colored.rgba != first.rgba)
        extended[35] = 2
        var additiveEffects = WorldEffects()
        additiveEffects.append(try GraphicEffect.decode(extended),at:0)
        let additive = try WorldRenderer.render(assets,x:2493,y:482,groundItems:additiveEffects.tiles(at:0,mobiles:[],items:[]))
        precondition(additive.missingCount == 0 && additive.rgba != colored.rgba)
        try additive.writeBMP(to:URL(fileURLWithPath:"build/spell-colored-additive.bmp"))
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
