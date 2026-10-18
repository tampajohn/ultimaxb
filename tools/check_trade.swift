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
  func event(_ type:NSEvent.EventType,_ point:NSPoint)->NSEvent {
   NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  }
  var moved:[Int] = []
  panel.onDrop = { item,point in precondition(item.serial == 3); moved.append(item.amount) }
  let destination = NSPoint(x:own.x+40,y:own.y+40)
  func dragStack() {
   panel.mouseDown(with:event(.leftMouseDown,own))
   panel.mouseUp(with:event(.leftMouseUp,destination))
  }
  dragStack()
  let picker = panel.subviews.compactMap { $0 as? StackQuantityPanel }.first!
  precondition(moved.isEmpty)
  let amount = picker.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
  amount.stringValue = "25"
  picker.subviews.compactMap { $0 as? NSButton }.first { $0.title == "OK" }!.performClick(nil)
  precondition(moved == [25] && picker.superview == nil)
  dragStack()
  let stalePicker = panel.subviews.compactMap { $0 as? StackQuantityPanel }.first!
  var revised = trade; revised.beginOfferChange(); panel.update(revised)
  precondition(stalePicker.superview == nil)
  stalePicker.onConfirm?(10)
  precondition(moved == [25])
  panel.update(trade)
  dragStack()
  let cancelledPicker = panel.subviews.compactMap { $0 as? StackQuantityPanel }.first!
  cancelledPicker.onCancel?()
  precondition(cancelledPicker.superview == nil && moved == [25])
  var accepted = false
  panel.onAccept = { value,revision in precondition(value && revision == trade.revision); accepted = true }
  let button = panel.subviews.compactMap { $0 as? NSButton }.first!
  button.performClick(nil); precondition(accepted)
  _ = try trade.setAccepted(true,revision:trade.revision); panel.update(trade)
  precondition(!button.isEnabled && panel.dropDestination(windowPoint:own) == nil)
  var cancelled = false; panel.onCancel = { cancelled = true }
  panel.rightMouseDown(with:NSEvent.mouseEvent(with:.rightMouseDown,location:own,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
  precondition(cancelled)
  print("Trade artwork, own-only drop region, explicit acceptance, pending lockout, partial-stack withdrawal, stale selection rejection and cancellation verified")
 }
}
