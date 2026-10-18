import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  precondition(assets.fonts?.count == 10, "Installed classic font records")
  let panel = JournalPanel(assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  var history = Journal()
  for i in 1...50 { history.append("Traveler: Journal fixture message \(i).") }
  panel.update(history)
  let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
  precondition(scroll.contentView.bounds.minY > 0)
  let end = scroll.contentView.bounds.minY
  let wheel = NSEvent(cgEvent:CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:80,wheel2:0,wheel3:0)!)!
  panel.scrollHistory(with:wheel)
  precondition(scroll.contentView.bounds.minY < end, "Wheel should browse older messages")
  let chat = ChatPanel(assets:assets)
  chat.append("Fixture history")
  var requests = 0, scrollRequests = 0
  chat.onHistoryRequested = { event in requests += 1; if event != nil { scrollRequests += 1 } }
  let historyButton = chat.subviews.compactMap { $0 as? NSButton }.first!
  precondition(historyButton.image != nil, "History control should use original journal artwork")
  historyButton.performClick(nil)
  chat.scrollWheel(with:wheel)
  let preview = chat.subviews.first { String(describing:type(of:$0)) == "ChatHistoryPreview" }!
  preview.scrollWheel(with:wheel)
  precondition(requests == 3 && scrollRequests == 2)
  chat.reset(); precondition(chat.history.lines.isEmpty && chat.isHidden)
  scroll.contentView.scroll(to:.zero)
  history.append("A new message arrives."); panel.update(history)
  precondition(scroll.contentView.bounds.minY == 0)
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/journal.png"))
  let unicode = JournalText(fonts:assets.fonts)
  unicode.setContents("Traveler: café — 界",width:120,minimumHeight:20)
  precondition(unicode.string == "Traveler: café — 界" && unicode.frame.height > 20)
  let fallback = JournalText(fonts:nil)
  fallback.setContents("Fallback text remains readable.",width:120,minimumHeight:20)
  precondition(fallback.frame.height > 20)
  history.clear(); panel.update(history)
  precondition((scroll.documentView as! JournalText).string.isEmpty)
  var closed = false; panel.onClose = { closed = true }
  panel.subviews.compactMap { $0 as? NSButton }.first!.performClick(nil)
  precondition(closed)
  print("Journal artwork, chat entry points, wheel scrolling, tail following, scroll preservation, clear and close verified")
 }
}
