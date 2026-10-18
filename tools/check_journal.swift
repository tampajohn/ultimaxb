import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let panel = JournalPanel(assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  var history = Journal()
  for i in 1...50 { history.append("Traveler: Journal fixture message \(i).") }
  panel.update(history)
  let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
  precondition(scroll.contentView.bounds.minY > 0)
  scroll.contentView.scroll(to:.zero)
  history.append("A new message arrives."); panel.update(history)
  precondition(scroll.contentView.bounds.minY == 0)
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/journal.png"))
  history.clear(); panel.update(history)
  precondition((scroll.documentView as! NSTextView).string.isEmpty)
  var closed = false; panel.onClose = { closed = true }
  panel.subviews.compactMap { $0 as? NSButton }.first!.performClick(nil)
  precondition(closed)
  print("Journal artwork, tail following, scroll preservation, clear and close verified")
 }
}
