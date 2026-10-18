import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  var packet = Data([0xAB,0,0,0,0,0,1,2,3])
  func text(_ s:String) { let bytes = Array(s.utf8)+[0]; packet.append(contentsOf:[0,UInt8(bytes.count)]+bytes) }
  text("Choose a quantity")
  packet.append(contentsOf:[1,2,0,0,0,50]); text("Enter a number from 0 to 50.")
  packet[1] = UInt8(packet.count>>8); packet[2] = UInt8(packet.count&255)
  let panel = TextPromptPanel(request:try TextPrompt.decode(packet),assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  let field = panel.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
  var replies:[Bool] = []; panel.onReply = { _,accepted in replies.append(accepted) }
  let buttons = panel.subviews.compactMap { $0 as? NSButton }
  field.stringValue = "51"; buttons[0].performClick(nil); precondition(replies.isEmpty)
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/text-prompt.png"))
  field.stringValue = "50"; buttons[0].performClick(nil); buttons[1].performClick(nil)
  precondition(replies == [true,false])
  print("Original text prompt rendered; invalid numeric input blocked, submit/cancel callbacks verified")
 }
}
