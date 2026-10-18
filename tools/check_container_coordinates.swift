import AppKit
import UOCore

@MainActor final class FlippedRoot: NSView { override var isFlipped: Bool { true } }
@main struct ContainerCoordinateCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        let root = FlippedRoot(frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
        window.contentView = root
        let source = try ContainerItem.decode(Data([0x25,0x40,0,0,3,0x0E,0xED,0,0,100,0,60,0,70,0x40,0,0,1,0,0]))[0]
        for serial: UInt8 in [1,2] {
            let panel = ContainerPanel(container: try OpenContainer.decode(Data([0x24,0x40,0,0,serial,0,60])), assets: assets)
            panel.frame.origin = NSPoint(x: 10 + Int(serial - 1) * 500, y: 35)
            root.addSubview(panel)
            let canvas = panel.subviews.first { String(describing: type(of: $0)) == "ContainerCanvas" }!
            let originalOrigin = panel.frame.origin
            func backgroundEvent(_ type:NSEvent.EventType,_ p:NSPoint)->NSEvent {
                NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            }
            canvas.mouseDown(with:backgroundEvent(.leftMouseDown,NSPoint(x:20,y:20)))
            canvas.mouseDragged(with:backgroundEvent(.leftMouseDragged,NSPoint(x:30,y:30)))
            canvas.mouseUp(with:backgroundEvent(.leftMouseUp,NSPoint(x:30,y:30)))
            precondition(panel.frame.origin != originalOrigin,"Background must drag the panel")
            panel.frame.origin = originalOrigin
            var closed = false; panel.onClose = { closed = true }
            canvas.mouseDown(with:backgroundEvent(.leftMouseDown,NSPoint(x:110,y:166)))
            canvas.mouseUp(with:backgroundEvent(.leftMouseUp,NSPoint(x:110,y:166)))
            precondition(closed,"Original minus must close the bag")
            let point = NSPoint(x: 90, y: 115)
            let windowPoint = canvas.convert(point, to: nil)
            guard let result = ContainerPanel.destination(in: root, windowPoint: windowPoint, item: source) else { fatalError("Container destination missed") }
            precondition(result.0 == 0x40000000 + UInt32(serial))
            precondition(abs(result.1.x - point.x) < 0.01 && abs(result.1.y - point.y) < 0.01)
            if serial == 1 {
                let gear = try ContainerItem.decode(Data([0x25,0x40,0,0,4,0x0F,0x51,0,0,178,0,60,0,70,0x40,0,0,1,0,0]))[0]
                panel.update([gear])
                var movedAmount: Int?
                panel.onMove = { _, amount, _, _, _ in movedAmount = amount }
                let sprite = try assets.sprite(gear.graphic + 0x4000)!
                let pixel = stride(from: 3, to: sprite.rgba.count, by: 4).first { sprite.rgba[$0] != 0 }! / 4
                let start = NSPoint(x: gear.x + pixel % sprite.width, y: gear.y + pixel / sprite.width)
                func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                let end = NSPoint(x: start.x + 20, y: start.y + 15)
                canvas.mouseDown(with: event(.leftMouseDown, start))
                canvas.mouseDragged(with: event(.leftMouseDragged, end))
                precondition(String(describing: type(of: root.subviews.last!)) == "ItemDragPreview", "Drag preview must be above panels")
                precondition(ContainerPanel.destination(in: root, windowPoint: canvas.convert(end, to: nil), item: gear)?.0 == 0x40000001, "Preview must not block drop hit testing")
                canvas.mouseUp(with: event(.leftMouseUp, end))
                precondition(movedAmount == 1, "Nonstackable gear must move one item despite amount=178")
                precondition(!panel.subviews.contains { $0 is StackQuantityPanel }, "Gear must not open the split dialog")
                var groundAmount: Int?
                panel.resolveDrop = { _,_ in nil }
                panel.onGroundDrop = { serial,amount,point in
                    precondition(serial == gear.serial)
                    groundAmount = amount; return true
                }
                canvas.mouseDown(with:event(.leftMouseDown,start))
                canvas.mouseDragged(with:event(.leftMouseDragged,NSPoint(x:400,y:300)))
                canvas.mouseUp(with:event(.leftMouseUp,NSPoint(x:400,y:300)))
                precondition(groundAmount == 1,"Drop outside containers must reach the ground handler")
                var autoPosition:NSPoint?
                panel.resolveDrop = { _,_ in (0x40000009,NSPoint(x:65535,y:65535)) }
                panel.onMove = { _,amount,x,y,_ in movedAmount = amount; autoPosition = NSPoint(x:x,y:y) }
                canvas.mouseDown(with:event(.leftMouseDown,start))
                canvas.mouseDragged(with:event(.leftMouseDragged,end))
                canvas.mouseUp(with:event(.leftMouseUp,end))
                precondition(autoPosition == NSPoint(x:65535,y:65535),"Automatic backpack coordinates must not subtract the sprite grab offset")
                panel.resolveDrop = nil
                panel.update([source]); movedAmount = nil
                let coins = try assets.sprite(source.displayGraphic + 0x4000)!
                let coinPixel = stride(from: 3, to: coins.rgba.count, by: 4).first { coins.rgba[$0] != 0 }! / 4
                let coinStart = NSPoint(x: source.x + coinPixel % coins.width, y: source.y + coinPixel / coins.width)
                let coinEnd = NSPoint(x: coinStart.x + 20, y: coinStart.y + 15)
                canvas.mouseDown(with: event(.leftMouseDown, coinStart))
                canvas.mouseDragged(with: event(.leftMouseDragged, coinEnd))
                precondition(!panel.subviews.contains { $0 is StackQuantityPanel }, "Wait until release before showing quantity")
                canvas.mouseUp(with: event(.leftMouseUp, coinEnd))
                precondition(panel.subviews.contains { $0 is StackQuantityPanel }, "Gold must open the split dialog")
                precondition(movedAmount == nil, "No move before quantity confirmation and destination")
            }
        }
        let outside = root.convert(NSPoint(x: 1190, y: 890), to: nil)
        precondition(ContainerPanel.destination(in: root, windowPoint: outside, item: source) == nil)
        print("Container coordinate checks passed: flipped root, 2× canvases, both containers, outside rejection")
    }
}
