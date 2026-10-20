import Foundation
import UOCore

@main struct Check {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let mount = EquippedItem(serial:2,graphic:0x3E9F,layer:25,owner:1,hue:0)
        let shirt = EquippedItem(serial:3,graphic:0x1517,layer:5,owner:1,hue:33)
        let pants = EquippedItem(serial:4,graphic:0x152E,layer:4,owner:1,hue:95)
        let equipment = [mount,shirt,pants]
        let mountBody = try assets.equipmentAnimation(graphic:mount.graphic)!
        precondition(mountBody == 820,"Chosen-era mounted horse animation comes from installed tiledata")
        for direction:UInt8 in 0..<8 {
            for body in [400,401] {
                for pace in 0...2 {
                    let moving = pace != 0
                    let mobile = WorldMobile(serial:1,body:body,x:2493,y:482,z:15,direction:direction | (pace == 2 ? 0x80 : 0))
                    let pose = MobilePresentation(x:2493,y:482,z:15,walking:moving,frame:moving ? 2 : 0)
                    let action = try MobileAnimation.action(for:mobile,pose:pose,equipment:equipment,assets:assets)
                    precondition(action == (pace == 2 ? 24 : moving ? 23 : 25))
                    let horse = try assets.animations!.frame(body:mountBody,direction:direction,action:action,frame:pose.frame)!
                    let frame = try WorldRenderer.render(assets,x:2493,y:482,mobiles:[mobile],equipment:equipment,mobilePresentations:[1:pose])
                    precondition(frame.missingCount == 0,"Mounted body, clothes and horse must have the selected animation")
                    let rider = try assets.animations!.frame(body:body,direction:direction,action:action,frame:pose.frame)!
                    let ax = frame.width/2, ay = frame.height/2-15*4
                    func alpha(_ f:AnimationFrame,_ x:Int,_ y:Int)->Bool {
                        let sx = ax-(f.mirrored ? f.sprite.width-f.centerX : f.centerX)
                        let sy = ay+22-f.sprite.height-f.centerY
                        let lx=x-sx, ly=y-sy
                        return lx>=0 && ly>=0 && lx<f.sprite.width && ly<f.sprite.height &&
                            f.sprite.rgba[(ly*f.sprite.width+(f.mirrored ? f.sprite.width-1-lx : lx))*4+3] != 0
                    }
                    let sx = ax-(horse.mirrored ? horse.sprite.width-horse.centerX : horse.centerX)
                    let sy = ay+22-horse.sprite.height-horse.centerY
                    var checked = false
                    outer: for y in sy..<sy+horse.sprite.height {
                        for x in sx..<sx+horse.sprite.width where alpha(horse,x,y) && !alpha(rider,x,y) {
                            let hit = try WorldHitTest.mobile(assets:assets,mobiles:[mobile],presentations:[1:pose],
                                camera:WorldCamera(x:2493,y:482),screenX:Double(x)+0.1,screenY:Double(y)+0.1,equipment:equipment)
                            precondition(hit?.serial == mobile.serial,"Horse-only pixels must select the rider")
                            checked = true; break outer
                        }
                    }
                    precondition(checked)
                    if direction == 2 && body == 400 && !moving {
                        try frame.writeBMP(to:URL(fileURLWithPath:"build/mounted-horse.bmp"))
                    }
                }
            }
        }
        print("Installed horse and clothed riders render in eight facings; horse-only pixels select the rider")
    }
}
