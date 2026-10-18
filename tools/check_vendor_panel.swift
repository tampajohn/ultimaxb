import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let item = ContainerItem(serial:20,graphic:0xF43,amount:2,x:0,y:0,container:100,hue:0)
  let offers = try VendorPackets.offers(Data([0x74,0,17,0,0,0,100,1,0,0,0,40,4,65,120,101,0]),contents:[item])
  let selling = CommandLine.arguments.contains("--sell")
  let panel = VendorPanel(serial:99,offers:Array(repeating:offers[0],count:12),assets:assets,selling:selling)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  panel.updateGold(123)
  panel.layoutSubtreeIfNeeded()
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:selling ? "build/vendor-sell-panel.png" : "build/vendor-panel.png"))
  let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
  let stack = scroll.documentView!.subviews.first as! NSStackView
  let row = stack.arrangedSubviews.first!
  let event = NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:2,pressure:1)!
  row.mouseDown(with:event)
  var purchased = false
  panel.onBuy = { quantities in precondition(quantities[20] == 1); purchased = true }
  panel.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == (selling ? "Sell selected items" : "Buy selected items") }!.performClick(nil)
  precondition(purchased)
  print("Vendor scroll artwork, gold display, double click and purchase callback passed")
 }
}
