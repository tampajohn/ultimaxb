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
  print("Dark world rendered with \(illuminated) locally illuminated pixels; \(darkened) pixels darkened")
 }
}
