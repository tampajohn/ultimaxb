import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let request = try HuePicker.decode(Data([0x95,0,0,0,1,0,0,0,0]))
  let panel = HuePickerPanel(request:request,assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  var selections:[Int] = []; panel.onChoose = { selections.append($0) }
  let p = panel.convert(NSPoint(x:34+8*4+2,y:34+8*2+2),to:nil)
  panel.mouseDown(with:NSEvent.mouseEvent(with:.leftMouseDown,location:p,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
  precondition(panel.selectedHue == 223 && selections.isEmpty)
  let shadePoint = panel.convert(NSPoint(x:180,y:145),to:nil)
  let shadeClick = NSEvent.mouseEvent(with:.leftMouseDown,location:shadePoint,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1)!
  panel.mouseDown(with:shadeClick); panel.mouseUp(with:shadeClick)
  precondition(panel.selectedHue == 226 && selections.isEmpty)
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/hue-picker.png"))
  panel.subviews.compactMap { $0 as? NSButton }.first!.performClick(nil)
  precondition(selections == [226])
  print("Original picker rendered; selection and shade preview without reply, explicit confirmation verified")
 }
}
