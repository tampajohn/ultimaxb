import AppKit
import UOCore
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let panel = CharacterPanel(assets:assets)
  let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView = panel
  let item = EquippedItem(serial:22,graphic:0xE86,layer:1,owner:1)
  let backpack = EquippedItem(serial:23,graphic:0xE75,layer:21,owner:1)
  panel.update(player:WorldMobile(serial:1,body:400,x:2572,y:308,z:30),equipment:[item,backpack])
  panel.layoutSubtreeIfNeeded()
  func descendants(_ v:NSView)->[NSView] { v.subviews.flatMap { [$0]+descendants($0) } }
  let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
  panel.cacheDisplay(in:panel.bounds,to:bitmap)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/classic-paperdoll.png"))
  var uses: [UInt32] = []
  panel.onUseEquipment = { uses.append($0) }
  let use = descendants(panel).compactMap { $0 as? NSButton }.first { $0.title == "Use" }!
  use.performClick(nil); precondition(uses == [22])
  let avatar = descendants(panel).first { String(describing:type(of:$0)) == "AvatarView" }!
  let layers = try Paperdoll.layers(assets:assets,body:400,hue:0,owner:1,equipment:[item])
  let sprite = layers.first { $0.item?.serial == 22 }!.sprite
  let offset = stride(from:3,to:sprite.rgba.count,by:4).first { sprite.rgba[$0] != 0 }!/4
  let point = avatar.convert(NSPoint(x:8+offset%sprite.width,y:19+offset/sprite.width),to:nil)
  let event = NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:2,pressure:1)!
  avatar.mouseUp(with:event); precondition(uses == [22,22])
  var drops:[UInt32] = []
  panel.onDropEquipment = { item,_ in drops.append(item.serial) }
  func mouse(_ type:NSEvent.EventType, _ p:NSPoint)->NSEvent {
   NSEvent.mouseEvent(with:type,location:p,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  }
  avatar.mouseDown(with:mouse(.leftMouseDown,point))
  let end = NSPoint(x:point.x+80,y:point.y+50)
  avatar.mouseDragged(with:mouse(.leftMouseDragged,end))
  avatar.mouseUp(with:mouse(.leftMouseUp,end))
  precondition(drops == [22]); precondition(uses == [22,22])
  let packLayers = try Paperdoll.layers(assets:assets,body:400,hue:0,owner:1,equipment:[backpack])
  let packSprite = packLayers.first { $0.item?.serial == 23 }!.sprite
  let packPixel = stride(from:3,to:packSprite.rgba.count,by:4).first { packSprite.rgba[$0] != 0 }!/4
  let packPoint = avatar.convert(NSPoint(x:8+packPixel%packSprite.width,y:19+packPixel/packSprite.width),to:nil)
  let pickaxe = ContainerItem(serial:22,graphic:0xE86,amount:1,x:0,y:0,container:0,hue:0)
  let ore = ContainerItem(serial:24,graphic:0x19B9,amount:8,x:0,y:0,container:0,hue:0)
  for drop in [pickaxe,ore] {
   let result = CharacterPanel.destination(in:panel,windowPoint:packPoint,item:drop)
   precondition(result?.0 == 23 && result?.1 == NSPoint(x:65535,y:65535))
  }
  let selfDrop = ContainerItem(serial:23,graphic:0xE75,amount:1,x:0,y:0,container:0,hue:0)
  precondition(panel.dropDestination(windowPoint:packPoint,item:selfDrop) == nil)
  precondition(panel.dropDestination(windowPoint:avatar.convert(NSPoint(x:190,y:50),to:nil),item:pickaxe) == nil)
  var packDrops:[UInt32] = []
  panel.onDropEquipment = { item,p in
   let inventory = ContainerItem(serial:item.serial,graphic:item.graphic,amount:1,x:0,y:0,container:0,hue:item.hue)
   if let target = CharacterPanel.destination(in:panel,windowPoint:p,item:inventory) { packDrops.append(target.0) }
  }
  avatar.mouseDown(with:mouse(.leftMouseDown,point))
  avatar.mouseDragged(with:mouse(.leftMouseDragged,packPoint))
  avatar.mouseUp(with:mouse(.leftMouseUp,packPoint))
  precondition(packDrops == [23])
  var targets:[UInt32] = []
  panel.onTarget = { targets.append($0); return true }
  avatar.mouseDown(with:mouse(.leftMouseDown,point))
  avatar.mouseDragged(with:mouse(.leftMouseDragged,packPoint))
  avatar.mouseUp(with:mouse(.leftMouseUp,packPoint))
  precondition(targets == [22] && packDrops == [23] && uses == [22,22])
  avatar.mouseDown(with:mouse(.leftMouseDown,packPoint))
  avatar.mouseUp(with:mouse(.leftMouseUp,packPoint))
  precondition(targets == [22,23])
  panel.update(player:WorldMobile(serial:1,body:400,x:2572,y:308,z:30),equipment:[])
  let body = try Paperdoll.layers(assets:assets,body:400,hue:0,owner:1,equipment:[]).first!.sprite
  let bodyPixel = stride(from:3,to:body.rgba.count,by:4).first { body.rgba[$0] != 0 }!/4
  let bodyPoint = avatar.convert(NSPoint(x:8+bodyPixel%body.width,y:19+bodyPixel/body.width),to:nil)
  avatar.mouseDown(with:mouse(.leftMouseDown,bodyPoint))
  avatar.mouseUp(with:mouse(.leftMouseUp,bodyPoint))
  precondition(targets == [22,23,1])
  print("Active paperdoll targeting selects equipment, backpack and body without use/drop side effects")
  print("Closed backpack icon accepts tools/ore at automatic coordinates; actual paperdoll drag resolves to bag; controls/self-drop rejected")
  print("Paperdoll drag dispatches equipment serial once, without use or splitting")
  print("Equipped pickaxe Use button and sprite double-click dispatch the correct serial")
 }
}
