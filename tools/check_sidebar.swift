import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory: URL(fileURLWithPath:"uo1998-client"))
  let sidebar = PlaySidebar(definitions:assets.skills)
  let window = NSWindow(contentRect:NSRect(x:0,y:0,width:280,height:700),styleMask:[.borderless],backing:.buffered,defer:false)
  window.contentView = sidebar
  var status = CharacterStatus(serial:1)
  try status.apply(Data([0xA1,0,0,0,1,0,60,0,42]))
  sidebar.updateStatus(status)
  sidebar.updateEquipment([EquippedItem(serial:2,graphic:0xE86,layer:2,owner:1)],player:1,assets:assets)
  var target = CombatTarget()
  try target.apply(Data([0xAA,0,0,0,9]))
  try target.apply(Data([0xA1,0,0,0,9,0,100,0,35]))
  sidebar.updateCombatTarget(target)
  sidebar.layoutSubtreeIfNeeded()
  precondition(sidebar.skills.frame.minY >= 300)
  precondition(sidebar.skills.frame.maxY <= sidebar.bounds.height)
  func descendants(_ v:NSView)->[NSView] { v.subviews.flatMap { [$0]+descendants($0) } }
  let labels = descendants(sidebar).compactMap { $0 as? NSTextField }
  precondition(labels.contains { $0.stringValue.contains("42 / 60") })
  precondition(labels.contains { $0.stringValue.contains("Health 35 / 100") })
  var commands:[Int] = []; sidebar.onCommand = {commands.append($0)}
  let use = descendants(sidebar).compactMap { $0 as? NSButton }.first { $0.title == "Use held tool · U" }!
  use.performClick(nil); precondition(commands == [2])
  let bitmap = sidebar.bitmapImageRepForCachingDisplay(in:sidebar.bounds)!
  sidebar.cacheDisplay(in:sidebar.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/sidebar.png"))
  print("Sidebar status, held-tool command, and dock bounds passed")
 }
}
