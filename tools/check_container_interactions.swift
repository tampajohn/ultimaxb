import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let container = try OpenContainer.decode(Data([0x24,0,0,0,10,0,0x3C]))
        let panel = ContainerPanel(container: container, assets: assets)
        let window = NSWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = panel
        let canvas = panel.subviews[0]
        let gold = ContainerItem(serial: 20, graphic: 0xEED, amount: 100, x: 60, y: 70, container: 10, hue: 0)
        panel.update([gold])
        let sprite = try assets.sprite(gold.displayGraphic + 0x4000)!
        let pixel = stride(from: 3, to: sprite.rgba.count, by: 4).first { sprite.rgba[$0] != 0 }! / 4
        let point = canvas.convert(NSPoint(x: gold.x + pixel % sprite.width, y: gold.y + pixel / sprite.width), to: nil)
        func event(_ type: NSEvent.EventType, shift: Bool = false) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: shift ? [.shift] : [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func snapshot() -> Data {
            let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        let ordinary = snapshot()
        canvas.mouseMoved(with: event(.mouseMoved))
        precondition(snapshot() != ordinary, "Opaque sprite hover should highlight")
        canvas.mouseExited(with: event(.mouseMoved))
        precondition(snapshot() == ordinary, "Exit should restore original art")
        var pickups: [(UInt32, Int)] = []
        var uses = 0, moves = 0
        panel.onQuickPickup = { pickups.append(($0, $1)) }
        panel.onUse = { _ in uses += 1 }
        panel.onMove = { _,_,_,_,_ in moves += 1 }
        canvas.mouseDown(with: event(.leftMouseDown, shift: true))
        canvas.mouseUp(with: event(.leftMouseUp, shift: true))
        precondition(pickups.count == 1 && pickups[0].0 == 20 && pickups[0].1 == 100)
        precondition(uses == 0 && moves == 0, "Quick pickup should not also use or drag")
        panel.onTarget = { _ in true }
        canvas.mouseDown(with: event(.leftMouseDown, shift: true))
        precondition(pickups.count == 1, "Target cursor must take priority")
        panel.onTarget = nil
        let sword = ContainerItem(serial: 21, graphic: 0xF5E, amount: 178, x: 60, y: 70, container: 10, hue: 0)
        panel.update([sword])
        let art = try assets.sprite(sword.displayGraphic + 0x4000)!
        let px = stride(from: 3, to: art.rgba.count, by: 4).first { art.rgba[$0] != 0 }! / 4
        let swordPoint = canvas.convert(NSPoint(x: sword.x + px % art.width, y: sword.y + px / art.width), to: nil)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: swordPoint, modifierFlags: [.shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: click)
        precondition(pickups.last?.0 == 21 && pickups.last?.1 == 1, "Non-stackable items always pick up one")
        print("Container hover, exit, stack pickup, target priority, and non-stackable pickup passed")
    }
}
