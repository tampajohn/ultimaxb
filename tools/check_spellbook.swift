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
  func click(_ y:CGFloat) {
   let p = panel.convert(NSPoint(x:70,y:y),to:nil)
   panel.mouseDown(with:NSEvent.mouseEvent(with:.leftMouseDown,location:p,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:2,pressure:1)!)
  }
  click(95); click(65)
  precondition(casts == [4])
  print("Original spellbook rendered; double-click Heal casts, unknown spell does not")
 }
}
