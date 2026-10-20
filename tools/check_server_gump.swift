import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let layout = "{ page 0 }{ resizepic 0 0 2600 600 240 }{ text 24 20 0 0 }{ tilepic 300 50 3907 }{ tilepichue 300 100 3907 33 }{ htmlgump 360 25 215 190 4 1 1 }{ page 1 }{ checkbox 24 60 210 211 0 9 }{ text 55 60 0 1 }{ textentry 24 100 270 25 0 4 2 }{ textentrylimited 24 190 270 25 0 5 5 3 }{ button 24 150 2225 2226 0 2 0 }{ page 2 }{ text 24 60 0 3 }{ button 24 100 2225 2226 1 0 7 }"
  var bytes:[UInt8] = [0xB0,0,0]
  bytes += [0,0,0,1,0,0,0,42,0,0,0,0,0,0,0,0]
  let encoded = Array(layout.utf8)
  bytes += [UInt8(encoded.count >> 8),UInt8(encoded.count & 255)] + encoded
  let texts = ["Server dialog", "Remember this choice", "Editable text", "Submit your selection", "<center><b>Crafting</b></center><basefont color=#882200>Choose a recipe.</basefont><br>Iron &amp; tools<br><i>Materials stay in your bag.</i><br>" + String(repeating:"More information.<br>",count:12), "A😀extra"]
  bytes += [0,UInt8(texts.count)]
  for text in texts {
   let units = Array(text.utf16); bytes += [UInt8(units.count >> 8),UInt8(units.count & 255)]
   for unit in units { bytes += [UInt8(unit >> 8),UInt8(unit & 255)] }
  }
  bytes[1] = UInt8(bytes.count >> 8); bytes[2] = UInt8(bytes.count & 255)
  let model = try ServerGump.decode(Data(bytes))
  let panel = ServerGumpPanel(definition:model,assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/server-gump.png"))
  let centerTile = try assets.gumps!.sprite(2604)!
  let tileLayout=Array("{ resizepic 0 0 2600 1300 800 }".utf8)
  var tilePacket:[UInt8]=[0xB0,0,0]+Array(bytes[3..<19])
  tilePacket += [UInt8(tileLayout.count>>8),UInt8(tileLayout.count&255)]+tileLayout+[0,0]
  tilePacket[1]=UInt8(tilePacket.count>>8); tilePacket[2]=UInt8(tilePacket.count&255)
  let tilePanel=ServerGumpPanel(definition:try ServerGump.decode(Data(tilePacket)),assets:assets)
  let tileWindow=NSWindow(contentRect:tilePanel.frame,styleMask:[.borderless],backing:.buffered,defer:false)
  tileWindow.contentView=tilePanel
  let tileBitmap=tilePanel.bitmapImageRepForCachingDisplay(in:tilePanel.bounds)!
  tilePanel.cacheDisplay(in:tilePanel.bounds,to:tileBitmap)
  let sx=CGFloat(tileBitmap.pixelsWide)/tilePanel.bounds.width,sy=CGFloat(tileBitmap.pixelsHigh)/tilePanel.bounds.height
  precondition(100+16+centerTile.width<1200)
  var samples=Set<String>()
  for dx in 0..<16 {
   let first=tileBitmap.colorAt(x:Int(CGFloat(100+dx)*sx),y:Int(200*sy))!
   let repeated=tileBitmap.colorAt(x:Int(CGFloat(100+dx+centerTile.width)*sx),y:Int(200*sy))!
   precondition(first == repeated,"Resizepic center must repeat at its source texture width")
   samples.insert(first.description)
  }
  precondition(samples.count>1,"The texture check must cover actual pattern detail")
  var replies = 0
  panel.onReply = { button,switches,entries in
   precondition(button == 7 && switches == [9] && entries.count == 2 && entries[0].0 == 4 && entries[0].1 == "Updated 😀" && entries[1].0 == 5 && entries[1].1 == "AB")
   replies += 1
  }
  let buttons = panel.subviews.compactMap { $0 as? NSButton }
  precondition(buttons.count == 3 && buttons[2].isHidden)
  buttons[0].performClick(nil)
  let field = panel.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
  precondition(field.font?.fontName == ClassicNativeFont.uiFont.fontName)
  field.stringValue = "Updated 😀"
  let limited=panel.subviews.compactMap { $0 as? NSTextField }.filter { $0.isEditable }[1]
  precondition(limited.stringValue == "A😀")
  limited.stringValue="AB😀"
  panel.controlTextDidChange(Notification(name:NSText.didChangeNotification,object:limited))
  precondition(limited.stringValue == "AB","Editing must respect UTF-16 limit without splitting the emoji")
  buttons[1].performClick(nil)
  precondition(replies == 0 && buttons[1].isHidden && !buttons[2].isHidden)
  buttons[2].performClick(nil)
  precondition(replies == 1)
  let formatted = GumpText.attributed("<b>Bold</b> &amp; &#x1F600;<br><i>Italic</i><img src='https://invalid.test/x'>",color:.white)
  precondition(formatted.string == "Bold & 😀\nItalic")
  let font = formatted.attribute(.font,at:0,effectiveRange:nil) as! NSFont
  precondition(font.fontName == ClassicNativeFont.uiFont.fontName)
  precondition((formatted.attribute(.strokeWidth,at:0,effectiveRange:nil) as? Double) == -2)
  let italicIndex=(formatted.string as NSString).range(of:"Italic").location
  precondition((formatted.attribute(.obliqueness,at:italicIndex,effectiveRange:nil) as? Double) == 0.2)
  precondition(formatted.attribute(.strokeWidth,at:italicIndex,effectiveRange:nil) == nil)
  let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
  precondition(scroll.documentView!.frame.height > scroll.contentSize.height)
  precondition((scroll.documentView as! NSTextView).string.contains("Iron & tools"))
  print("Original-art dialog rendered; page switch, checkbox and Unicode entry reply verified locally")
 }
}
