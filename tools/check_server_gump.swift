import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let layout = "{ page 0 }{ resizepic 0 0 2600 360 240 }{ text 24 20 0 0 }{ page 1 }{ checkbox 24 60 210 211 0 9 }{ text 55 60 0 1 }{ textentry 24 100 270 25 0 4 2 }{ button 24 150 2225 2226 0 2 0 }{ page 2 }{ text 24 60 0 3 }{ button 24 100 2225 2226 1 0 7 }"
  var bytes:[UInt8] = [0xB0,0,0]
  bytes += [0,0,0,1,0,0,0,42,0,0,0,0,0,0,0,0]
  let encoded = Array(layout.utf8)
  bytes += [UInt8(encoded.count >> 8),UInt8(encoded.count & 255)] + encoded
  let texts = ["Server dialog", "Remember this choice", "Editable text", "Submit your selection"]
  bytes += [0,UInt8(texts.count)]
  for text in texts {
   let units = Array(text.utf16); bytes += [0,UInt8(units.count)]
   for unit in units { bytes += [UInt8(unit >> 8),UInt8(unit & 255)] }
  }
  bytes[1] = UInt8(bytes.count >> 8); bytes[2] = UInt8(bytes.count & 255)
  let model = try ServerGump.decode(Data(bytes))
  let panel = ServerGumpPanel(definition:model,assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/server-gump.png"))
  var replies = 0
  panel.onReply = { button,switches,entries in
   precondition(button == 7 && switches == [9] && entries.count == 1 && entries[0].0 == 4 && entries[0].1 == "Updated 😀")
   replies += 1
  }
  let buttons = panel.subviews.compactMap { $0 as? NSButton }
  precondition(buttons.count == 3 && buttons[2].isHidden)
  buttons[0].performClick(nil)
  let field = panel.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
  field.stringValue = "Updated 😀"
  buttons[1].performClick(nil)
  precondition(replies == 0 && buttons[1].isHidden && !buttons[2].isHidden)
  buttons[2].performClick(nil)
  precondition(replies == 1)
  print("Original-art dialog rendered; page switch, checkbox and Unicode entry reply verified locally")
 }
}
