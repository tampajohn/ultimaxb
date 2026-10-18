import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let corpse = try OpenContainer.decode(Data([0x24,0,0,0,10,0,9]))
        let panel = ContainerPanel(container: corpse, assets: assets)
        let window = NSWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = panel
        let canvas = panel.subviews[0]
        // Identical art/positions deliberately guarantee the appearance entry covers loot.
        let loot = ContainerItem(serial:20,graphic:0x1BDD,amount:30,x:80,y:155,container:10,hue:0)
        let decoration = ContainerItem(serial:21,graphic:loot.graphic,amount:0,x:80,y:155,container:10,hue:0)
        panel.update([loot,decoration])
        let sprite = try assets.sprite(loot.displayGraphic+0x4000)!
        let pixel = stride(from:3,to:sprite.rgba.count,by:4).first { sprite.rgba[$0] != 0 }! / 4
        let point = canvas.convert(NSPoint(x:loot.x+pixel%sprite.width,y:loot.y+pixel/sprite.width),to:nil)
        var selected:UInt32?, quantity:Int?
        panel.onQuickPickup = { selected = $0; quantity = $1 }
        func click() {
            let event = NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[.shift],timestamp:0,
                windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            canvas.mouseDown(with:event)
        }
        click()
        precondition(selected == loot.serial && quantity == 30, "Loot must be selectable through hidden corpse appearance entries")
        selected = nil
        panel.update([decoration]); click()
        precondition(selected == nil, "Corpse appearance records must not be pickable")
        // Ordinary containers can legitimately have non-stackable zero-amount items.
        let bag = ContainerPanel(container:try OpenContainer.decode(Data([0x24,0,0,0,10,0,0x3C])),assets:assets)
        window.contentView = bag
        bag.update([ContainerItem(serial:22,graphic:0xA0F,amount:0,x:60,y:70,container:10,hue:0)])
        let candle = try assets.sprite(0xA0F+0x4000)!
        let px = stride(from:3,to:candle.rgba.count,by:4).first { candle.rgba[$0] != 0 }! / 4
        let bagPoint = bag.subviews[0].convert(NSPoint(x:60+px%candle.width,y:70+px/candle.width),to:nil)
        bag.onQuickPickup = { selected = $0; quantity = $1 }
        bag.subviews[0].mouseDown(with:NSEvent.mouseEvent(with:.leftMouseDown,location:bagPoint,modifierFlags:[.shift],timestamp:0,
            windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!)
        precondition(selected == 22 && quantity == 1)
        print("Corpse loot selection ignores zero-quantity decorations; ordinary container items remain selectable")
    }
}
