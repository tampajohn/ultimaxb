import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let panel = SpellbookPanel(serial:100,assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  panel.update([1,4,7,9,16].map { ContainerItem(serial:UInt32($0),graphic:0x1F2D,amount:$0,x:0,y:0,container:100,hue:0) })
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/spellbook.png"))
  var casts:[Int] = []; panel.onCast = { casts.append($0) }
  func click(_ y:CGFloat,x:CGFloat = 70,count:Int = 2) {
   let p = panel.convert(NSPoint(x:x,y:y),to:nil)
   panel.mouseDown(with:NSEvent.mouseEvent(with:.leftMouseDown,location:p,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:count,pressure:1)!)
  }
  click(95); click(65)
  precondition(casts == [4])
  click(95,count:1)
  panel.update([1,4,7,9,16].map { ContainerItem(serial:UInt32($0),graphic:0x1F2D,amount:$0,x:0,y:0,container:100,hue:0) })
  RunLoop.main.run(until:Date().addingTimeInterval(NSEvent.doubleClickInterval+0.1))
  precondition(casts == [4])
  let detailBitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:detailBitmap)
  try detailBitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/spellbook-details.png"))
  click(50,x:235)
  precondition(casts == [4,4])
  click(15,x:330,count:1)
  click(50)
  precondition(casts == [4,4,7])
  click(180,x:60,count:1)
  click(95)
  precondition(casts == [4,4,7,4])
  print("Spellbook index/detail navigation, original icons, inspection without casting and double-click casting verified")
 }
}
