import Foundation
@testable import UOCore

@main struct CheckDeathAnimation {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let mobile = WorldMobile(serial:1,body:400,x:2603,y:309,z:15,direction:3)
        for alternate in [false,true] {
            let event = try MobileDeath.decode(Data([0xAF,0,0,0,1,0x40,0,0,2,0,0,0,alternate ? 1 : 0]))
            let action = CorpseArt.deathAction(body:400,alternate:alternate)
            let count = try assets.animations!.frameCount(body:400,direction:3,action:action)!
            precondition(count > 1)
            var deaths = DeathAnimations()
            deaths.play(event,mobile:mobile,equipment:[],pose:nil,frames:count,at:0)
            func render(_ time:Double) throws -> Frame {
                try WorldRenderer.render(assets,x:2603,y:309,mobiles:deaths.mobiles,
                    mobilePresentations:deaths.presentations(at:time))
            }
            let start = try render(0), end = try render(Double(count-1)*0.1+0.001)
            precondition(start.rgba != end.rgba,"Death animation must progress through different frames")
            try start.writeBMP(to:URL(fileURLWithPath:"build/death-\(action)-start.bmp"))
            try end.writeBMP(to:URL(fileURLWithPath:"build/death-\(action)-end.bmp"))
            let corpse = try CorpseArt.frame(body:400,direction:alternate ? 0x83 : 3,assets:assets)!
            let last = try assets.animations!.frame(body:400,direction:3,action:action,frame:count-1)!
            precondition(corpse.sprite.rgba == last.sprite.rgba,"Corpse pose must match the final fall frame")
            deaths.expire(at:Double(count)*0.1)
            precondition(!deaths.isAnimating && deaths.hiddenCorpses.isEmpty)
        }
        print("Installed animations: both human death variants progress, expire, and match final corpse art")
    }
}
