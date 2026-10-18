import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let panel = CharacterCreationPanel(assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  var packet = Data([0xA9,0,68,0,1,0])
  packet.append(contentsOf:Array("Britain".utf8)+Array(repeating:0,count:24))
  packet.append(contentsOf:Array("Inn".utf8)+Array(repeating:0,count:28))
  panel.configure(cities:try CharacterList.decode(packet).cities)
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/character-creation.png"))
  var submitted = false
  panel.onCreate = { _,_,_,a,appearance in precondition(appearance.isValid(female:false)); precondition(a.validationMessage == nil); submitted = true }
  panel.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Create Character" }!.performClick(nil)
  precondition(submitted)
  panel.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Appearance…" }!.performClick(nil)
  let editor = panel.subviews.compactMap { $0 as? AppearanceEditor }.first!
  let popups = editor.subviews.compactMap { $0 as? NSPopUpButton }
  popups[0].selectItem(withTag:0x410); popups[1].selectItem(withTag:0x203B); popups[3].selectItem(withTag:0x2040)
  NSApp.sendAction(popups[1].action!,to:popups[1].target,from:popups[1])
  precondition(editor.selection.hairStyle == 0x203B && editor.selection.beardStyle == 0x2040)
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/character-appearance.png"))
  editor.setFemale(true)
  precondition(editor.selection.beardStyle == 0 && !popups[3].isEnabled)
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/character-appearance-female.png"))
  print("Creation preview and allocation submission passed")
 }
}
