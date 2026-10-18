import Foundation
import UOCore
@main struct Check {
 static func main() throws {
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let action = try MobileAction.decode(Data([0x6E,0,0,0,1,0,11,0,0,0,1,0,0,0]))
  let count = try assets.animations!.frameCount(body:400,direction:2,action:11)!
  let toolBody = try assets.equipmentAnimation(graphic:0xE86)!
  let bodyA = try assets.animations!.frame(body:400,direction:2,action:11,frame:0)!
  let bodyB = try assets.animations!.frame(body:400,direction:2,action:11,frame:min(2,count-1))!
  let tool = try assets.animations!.frame(body:toolBody,direction:2,action:11,frame:1)
  precondition(bodyA.sprite.rgba != bodyB.sprite.rgba && tool != nil)
  var motion = MobileMotion()
  motion.update([WorldMobile(serial:1,body:400,x:2600,y:463,z:60)],at:0)
  motion.play(action,frames:count,at:1)
  precondition(motion.presentations(at:1.33)[1]?.action == 11)
  print("Real client assets: mining body changes frames and equipped pickaxe action exists (\(count) frames)")
 }
}
