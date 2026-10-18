import Foundation
import UOCore
@main struct Check {
 static func main() throws {
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let animation = try assets.equipmentAnimation(graphic:0xE86)!
  for body in [400,401] {
   for direction in UInt8(0)...7 {
    for action in [7,8,15,3,11] {
     let bodyFrame = try assets.animations!.frame(body:body,direction:direction,action:action)
     precondition(bodyFrame != nil)
     let toolFrame = try assets.animations!.frame(body:animation,direction:direction,action:action)
     precondition(toolFrame != nil)
    }
    let mobile = WorldMobile(serial:1,body:body,x:2600,y:463,z:0,direction:direction,flags:0x40)
    let frame = try assets.animations!.frame(body:body,direction:direction,action:7)!
    let sprite = frame.sprite
    let pixel = stride(from:3,to:sprite.rgba.count,by:4).first { sprite.rgba[$0] != 0 }!/4
    let px = pixel%sprite.width, py = pixel/sprite.width
    let sx = 480-(frame.mirrored ? sprite.width-frame.centerX : frame.centerX)
    let sy = 360+22-sprite.height-frame.centerY
    let hit = try WorldHitTest.mobile(assets:assets,mobiles:[mobile],presentations:[:],camera:WorldCamera(x:2600,y:463),screenX:Double(sx+(frame.mirrored ? sprite.width-1-px : px)),screenY:Double(sy+py))
    precondition(hit?.serial == 1)
   }
  }
  print("Male/female war stances, combat walking, armed running, and pickaxe layers exist in every direction; war stance hit tests align")
 }
}
