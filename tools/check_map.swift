import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let panel = MapPanel(assets:assets)
  let player = WorldMobile(serial:1,body:400,x:2477,y:411,z:15)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false)
  window.contentView = panel
  panel.update(player:player,mobiles:[player,WorldMobile(serial:2,body:225,x:2480,y:412,z:15)])
  func save(_ name:String) throws {
   let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
   panel.cacheDisplay(in:panel.bounds,to:bitmap)
   try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/"+name+".png"))
  }
  try save("map-local")
  var destinations:[(Int,Int)] = []
  panel.onTravel = { destinations.append(($0,$1)) }
  let point = panel.convert(NSPoint(x:160,y:140),to:nil)
  let click = NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:.shift,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  panel.mouseDown(with:click)
  precondition(destinations.count == 1 && destinations[0].0 == 2487 && destinations[0].1 == 401)

  panel.toggleMode()
  try save("map-world")
  print("Local and world maps rendered with installed assets")
 }
}
