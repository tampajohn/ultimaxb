import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  var trade = SecureTrade(event:.opened(partner:1,ownContainer:10,otherContainer:20,name:"Trader"))!
  trade.update(items:[ContainerItem(serial:3,graphic:0xEED,amount:100,x:15,y:15,container:10,hue:0),ContainerItem(serial:4,graphic:0xF43,amount:1,x:30,y:20,container:20,hue:0)])
  let panel = TradePanel(trade:trade,assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/trade.png"))
  let own = panel.convert(NSPoint(x:60,y:85),to:nil), other = panel.convert(NSPoint(x:210,y:90),to:nil)
  precondition(panel.dropDestination(windowPoint:own)?.0 == 10)
  precondition(panel.dropDestination(windowPoint:other) == nil)
  var accepted = false
  panel.onAccept = { value,revision in precondition(value && revision == trade.revision); accepted = true }
  let button = panel.subviews.compactMap { $0 as? NSButton }.first!
  button.performClick(nil); precondition(accepted)
  _ = try trade.setAccepted(true,revision:trade.revision); panel.update(trade)
  precondition(!button.isEnabled && panel.dropDestination(windowPoint:own) == nil)
  var cancelled = false; panel.onCancel = { cancelled = true }
  panel.rightMouseDown(with:NSEvent.mouseEvent(with:.rightMouseDown,location:own,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
  precondition(cancelled)
  print("Trade artwork, own-only drop region, explicit acceptance, pending lockout and cancellation verified")
 }
}
