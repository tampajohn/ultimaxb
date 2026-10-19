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
  panel.update([1,2,3,4,7,9,16].map { ContainerItem(serial:UInt32($0),graphic:0x1F2D,amount:$0,x:0,y:0,container:100,hue:0) })
  click(50)
  precondition(casts == [4,4,7,7])
  click(180,x:60,count:1)
  click(95)
  precondition(casts == [4,4,7,7,4])
  var shortcuts:[Int] = []
  panel.onShortcut = { id,_ in shortcuts.append(id) }
  click(95,count:1)
  func drag(_ x:CGFloat,_ y:CGFloat) {
   let point = panel.convert(NSPoint(x:x,y:y),to:nil)
   panel.mouseDragged(with:NSEvent.mouseEvent(with:.leftMouseDragged,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
  }
  drag(72,95); precondition(shortcuts.isEmpty)
  drag(300,200); precondition(shortcuts == [4])
  precondition(casts == [4,4,7,7,4])
  let shortcut = SpellShortcut(spell:4,assets:assets)
  panel.addSubview(shortcut)
  shortcut.place(at:NSPoint(x:1000,y:-100),in:panel)
  precondition(shortcut.frame.maxX <= panel.bounds.maxX && shortcut.frame.minY == 0)
  var shortcutCasts = 0, closed = false
  shortcut.onCast = { shortcutCasts += 1 }; shortcut.onClose = { closed = true }
  let event = NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:2,pressure:1)!
  shortcut.mouseDown(with:event); precondition(shortcutCasts == 1)
  shortcut.rightMouseDown(with:event); precondition(closed && shortcut.superview == nil)
  print("Spellbook details, drag threshold, shortcut placement/casting/removal and unknown-spell rejection verified")
 }
}
