import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  var data = Data([0x7C,0,0,0x40,0,0,1,0,9,6])+Data("Choose".utf8)+Data([2])
  data += Data([0x0F,0x49,0,0,3])+Data("Axe".utf8)
  data += Data([0x0F,0x5C,0,0,4])+Data("Mace".utf8)
  data[2] = UInt8(data.count)
  let menu = try ServerMenu.decode(data)
  let panel = ServerMenuPanel(menu:menu,assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/server-menu.png"))
  var choice:Int?; panel.onChoose = { choice = $0 }
  let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
  let buttons = scroll.documentView!.subviews.compactMap { $0 as? NSButton }
  buttons[1].performClick(nil); precondition(choice == 2)
  print("Original icon menu rendered; second option retains server choice 2")
 }
}
