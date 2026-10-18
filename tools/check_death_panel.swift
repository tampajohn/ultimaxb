import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let panel = DeathPanel(assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  var state = DeathState(); try state.apply(Data([0x2C,0])); panel.update(state)
  var choice:Bool?; panel.onChoice = { choice = $0 }
  let buttons = panel.subviews.compactMap { $0 as? NSButton }
  buttons.first { $0.title == "Request resurrection" }!.performClick(nil)
  precondition(choice == true)
  _ = try state.response(resurrect:true); panel.update(state)
  precondition(buttons.allSatisfy { !$0.isEnabled })
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/death-panel.png"))
  print("Death choice callback and waiting-state controls verified; no network request sent")
 }
}
