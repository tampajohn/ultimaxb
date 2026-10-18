import AppKit
import UOCore
@main struct Check {
 static func main() throws {
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  var lighting = WorldLighting(); try lighting.apply(Data([0x4F,26]),player:1)
  let day = try WorldRenderer.render(assets,x:2477,y:411)
  let night = try WorldRenderer.render(assets,x:2477,y:411,lighting:lighting)
  precondition(day.rgba != night.rgba)
  let ambient = UInt16((lighting.brightness*255).rounded())
  var illuminated = 0, darkened = 0
  for i in stride(from:0,to:day.rgba.count,by:4) where day.rgba[i]>20 {
   if UInt16(night.rgba[i]) > UInt16(day.rgba[i])*ambient/255+2 { illuminated += 1 }
   if night.rgba[i] < day.rgba[i] { darkened += 1 }
  }
  precondition(illuminated>100 && darkened>100)
  try night.writeBMP(to:URL(fileURLWithPath:"build/minoc-night.bmp"))
  let bitmap = NSBitmapImageRep(data:try Data(contentsOf:URL(fileURLWithPath:"build/minoc-night.bmp")))!
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/minoc-night.png"))
  let mobile = WorldMobile(serial:1,body:400,x:2477,y:411,z:0,direction:3)
  let lantern = EquippedItem(serial:2,graphic:0xA15,layer:2,owner:1)
  let unlit = try WorldRenderer.render(assets,x:2477,y:411,mobiles:[mobile],lighting:lighting)
  let carried = try WorldRenderer.render(assets,x:2477,y:411,mobiles:[mobile],equipment:[lantern],lighting:lighting)
  var brightGround = 0
  for yy in 405..<450 {
   for xx in 440..<520 {
    let p = (yy*960+xx)*4
    if carried.rgba[p]>unlit.rgba[p]+10 { brightGround += 1 }
   }
  }
  precondition(brightGround>100)
  let absentOwner = try WorldRenderer.render(assets,x:2477,y:411,equipment:[lantern],lighting:lighting)
  precondition(absentOwner.rgba == night.rgba)
  let removed = try WorldRenderer.render(assets,x:2477,y:411,mobiles:[mobile],lighting:lighting)
  precondition(removed.rgba == unlit.rgba)
  var motion = MobileMotion()
  motion.update([mobile],at:0)
  let moved = WorldMobile(serial:1,body:400,x:2478,y:411,z:0,direction:3)
  motion.update([moved],at:0.01)
  let interpolated = try WorldRenderer.render(assets,x:2477,y:411,mobiles:[moved],equipment:[lantern],mobilePresentations:motion.presentations(at:0.01),lighting:lighting)
  // At the start of movement, the light must still be at the previous tile.
  for yy in 410..<440 {
   for xx in 450..<510 {
    let p = (yy*960+xx)*4
    precondition(interpolated.rgba[p] == carried.rgba[p])
   }
  }
  try carried.writeBMP(to:URL(fileURLWithPath:"build/carried-lantern.bmp"))
  let carriedBitmap = NSBitmapImageRep(data:try Data(contentsOf:URL(fileURLWithPath:"build/carried-lantern.bmp")))!
  try carriedBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/carried-lantern.png"))
  print("Carried lantern lights ground, follows interpolated position and disappears on unequip/owner removal")
  print("Dark world rendered with \(illuminated) locally illuminated pixels; \(darkened) pixels darkened")
 }
}
