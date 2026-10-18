import AppKit
import UOCore

@MainActor
final class ContainerPanel: NSView {
    let serial: UInt32
    private let canvas: ContainerCanvas
    private lazy var classicCursor = ClassicCursor(assets: canvas.assets)
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: classicCursor.cursor())
    }
    private let caption = NSTextField(labelWithString: "Double-click an item to use it.")
    var onTarget: ((UInt32) -> Bool)? { didSet { canvas.onTarget = onTarget } }
    var onMove: ((UInt32, Int, Int, Int, UInt32) -> Void)? {
        didSet { canvas.onMove = onMove }
    }
    var onGroundDrop: ((UInt32,Int,NSPoint)->Bool)? { didSet { canvas.onGroundDrop = onGroundDrop } }
    static func destination(in root: NSView, windowPoint: NSPoint, item: ContainerItem) -> (UInt32, NSPoint)? {
        var hit = root.hitTest(root.superview?.convert(windowPoint, from: nil) ?? windowPoint)
        while let current = hit {
            if let trade = current as? TradePanel { return trade.dropDestination(windowPoint:windowPoint) }
            if let container = current as? ContainerPanel {
                return container.dropDestination(windowPoint: windowPoint, item: item)
            }
            hit = current.superview
        }
        return nil
    }
    var resolveDrop: ((NSPoint, ContainerItem) -> (UInt32, NSPoint)?)? {
        didSet { canvas.resolveDrop = resolveDrop }
    }
    func dropDestination(windowPoint: NSPoint, item: ContainerItem) -> (UInt32, NSPoint)? {
        canvas.dropDestination(windowPoint: windowPoint, item: item)
    }
    private var panelDragOrigin: NSPoint?
    override func mouseDown(with event: NSEvent) {
        guard let parent = superview else { return }
        panelDragOrigin = parent.convert(event.locationInWindow, from: nil)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview, let old = panelDragOrigin else { return }
        let point = parent.convert(event.locationInWindow, from: nil)
        frame.origin.x = min(max(0, frame.origin.x + point.x - old.x), max(0, parent.bounds.width - frame.width))
        frame.origin.y = min(max(0, frame.origin.y + point.y - old.y), max(0, parent.bounds.height - 80))
        panelDragOrigin = point
    }
    override func mouseUp(with event: NSEvent) { panelDragOrigin = nil }
    private var quantityPanel: StackQuantityPanel?
    func showMessage(_ message: String) { caption.stringValue = message }
    var onClose: (() -> Void)?
    var onUse: ((UInt32) -> Void)? {
        didSet { canvas.onUse = onUse }
    }
    override var isFlipped: Bool { true }
    init(container: OpenContainer, assets: ClientAssets) {
        serial = container.serial
        let background = try? assets.gumps?.sprite(Int(container.graphic))
        canvas = ContainerCanvas(assets: assets, background: background, serial: container.serial)
        let width = CGFloat(background?.width ?? 300) * 2
        let height = CGFloat(background?.height ?? 260) * 2
        super.init(frame:NSRect(x:250,y:20,width:width,height:height))
        canvas.frame = NSRect(x:0,y:0,width:width,height:height)
        canvas.bounds = NSRect(x:0,y:0,width:width/2,height:height/2)
        addSubview(canvas)
        canvas.onClose = { [weak self] in self?.onClose?() }
        if container.graphic == 0x3C { canvas.closeArea = NSRect(x:105,y:162,width:16,height:16) }
        Telemetry.shared.record("container_art", ["gump": container.graphic, "loaded": background != nil])
        canvas.onSplit = { [weak self] item in
            guard let self, self.quantityPanel == nil else { return }
            let picker = StackQuantityPanel(maximum: item.amount, assets: assets)
            picker.onConfirm = { [weak self, weak picker] amount in
                Telemetry.shared.record("inventory_split_confirmed", ["serial": item.serial, "amount": amount])
                self?.canvas.chooseAmount(amount)
                picker?.removeFromSuperview(); self?.quantityPanel = nil
                if let view = self?.superview { view.window?.makeFirstResponder(view) }
                self?.caption.stringValue = "Click a position or matching stack to drop. Right-click to cancel."
            }
            picker.onCancel = { [weak self, weak picker] in
                self?.canvas.cancelDrag(); picker?.removeFromSuperview(); self?.quantityPanel = nil
                if let view = self?.superview { view.window?.makeFirstResponder(view) }
            }
            self.quantityPanel = picker; self.addSubview(picker)
            Telemetry.shared.record("inventory_split_opened", ["serial": item.serial, "amount": item.amount])
        }
        canvas.onSelect = { [weak self] text in self?.caption.stringValue = text }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func update(_ items: [ContainerItem]) {
        let contents = items.filter { $0.container == serial }.sorted { $0.serial < $1.serial }
        guard contents != canvas.items else { return }
        canvas.items = contents
        for item in canvas.items {
            let sprite = try? canvas.assets.sprite(item.displayGraphic + 0x4000)
            Telemetry.shared.record("container_item_art", ["serial": item.serial, "graphic": item.graphic,
                "display_graphic": item.displayGraphic, "amount": item.amount, "x": item.x, "y": item.y,
                "visible_pixels": sprite?.rgba.enumerated().filter { $0.offset % 4 == 3 && $0.element != 0 }.count ?? 0])
        }
        canvas.needsDisplay = true
    }
    @objc private func closePanel() { onClose?() }
}

@MainActor
private final class ContainerCanvas: NSView {
    let assets: ClientAssets
    let background: Sprite?
    let serial: UInt32
    var onClose: (() -> Void)?
    var closeArea: NSRect?
    private var closing = false
    var onGroundDrop: ((UInt32,Int,NSPoint)->Bool)?
    var onTarget: ((UInt32) -> Bool)?
    var onMove: ((UInt32, Int, Int, Int, UInt32) -> Void)?
    var onSplit: ((ContainerItem) -> Void)?
    var resolveDrop: ((NSPoint, ContainerItem) -> (UInt32, NSPoint)?)?
    private var placementMonitor: Any?
    func dropDestination(windowPoint: NSPoint, item: ContainerItem) -> (UInt32, NSPoint)? {
        let point = convert(windowPoint, from: nil)
        guard bounds.contains(point) else { return nil }
        let target = hit(at: point, excluding: item.serial)
        let destination = target.flatMap { target -> UInt32? in
            if target.graphic == item.graphic && target.hue == item.hue && ((try? assets.isStackable(graphic: item.graphic)) == true) { return target.serial }
            if ((try? assets.itemFlags(graphic: target.graphic)) ?? 0) & 0x00200000 != 0 { return target.serial }
            return nil
        }
        return (destination ?? serial, point)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelDrag() }
    }
    private var dragPreview: ItemDragPreview?
    private func updateDragPreview() {
        guard dragging, !choosing, let item = candidate, let root = superview?.superview,
              let sprite = try? assets.sprite(item.displayGraphic + 0x4000) else { dragPreview?.removeFromSuperview(); dragPreview = nil; return }
        let overlay: ItemDragPreview
        if let existing = dragPreview { overlay = existing }
        else {
            overlay = ItemDragPreview(frame: root.bounds)
            overlay.autoresizingMask = [.width, .height]
            dragPreview = overlay; root.addSubview(overlay)
        }
        let start = root.convert(NSPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y), from: self)
        let end = root.convert(NSPoint(x: pointer.x - grabOffset.x + Double(sprite.width), y: pointer.y - grabOffset.y + Double(sprite.height)), from: self)
        overlay.sprite = sprite
        overlay.destination = NSRect(x: start.x, y: start.y, width: end.x-start.x, height: end.y-start.y)
        overlay.needsDisplay = true
    }
    private var candidate: ContainerItem?
    private var origin = NSPoint.zero
    private var grabOffset = NSPoint.zero
    private var pointer = NSPoint.zero
    private var dragging = false
    private var choosing = false
    private var chosenAmount: Int?
    func chooseAmount(_ amount: Int) {
        choosing = false; chosenAmount = amount; needsDisplay = true; updateDragPreview()
        placementMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            guard let self, event.window === self.window, self.chosenAmount != nil else { return event }
            if event.type == .rightMouseDown { self.cancelDrag(); return nil }
            if event.type == .leftMouseDown {
                self.finishDrop(at: self.convert(event.locationInWindow, from: nil)); return nil
            }
            self.pointer = self.convert(event.locationInWindow, from: nil); self.needsDisplay = true; self.updateDragPreview()
            return event
        }
    }
    func cancelDrag() { dragPreview?.removeFromSuperview(); dragPreview = nil; if let placementMonitor { NSEvent.removeMonitor(placementMonitor); self.placementMonitor = nil }; candidate = nil; dragging = false; choosing = false; chosenAmount = nil; needsDisplay = true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) { pointer = convert(event.locationInWindow, from: nil); if dragging { needsDisplay = true; updateDragPreview() } }
    override func rightMouseDown(with event: NSEvent) { if candidate != nil { cancelDrag() } else { onClose?() } }
    override func mouseDragged(with event: NSEvent) {
        if closing { return }
        guard let candidate else { superview?.mouseDragged(with:event); return }
        guard !choosing else { return }
        pointer = convert(event.locationInWindow, from: nil)
        if !dragging, hypot(pointer.x - origin.x, pointer.y - origin.y) > 3 {
            dragging = true
            if candidate.amount > 1 && ((try? assets.isStackable(graphic: candidate.graphic)) == true) { choosing = true }
        }
        needsDisplay = true; updateDragPreview()
    }
    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with:event)
        if closing { closing = false; if closeArea?.contains(convert(event.locationInWindow,from:nil)) == true { onClose?() }; return }
        if dragging, choosing, let candidate { onSplit?(candidate); return }
        guard dragging, !choosing, chosenAmount == nil else { return }
        finishDrop(at: convert(event.locationInWindow, from: nil))
    }
    private func finishDrop(at point: NSPoint) {
        guard let item = candidate else { cancelDrag(); return }
        let windowPoint = convert(point, to: nil)
        let resolved = resolveDrop.map { $0(windowPoint, item) } ?? dropDestination(windowPoint: windowPoint, item: item)
        let amount = ((try? assets.isStackable(graphic: item.graphic)) == true) ? (chosenAmount ?? max(1, item.amount)) : 1
        guard let (target, destination) = resolved else {
            _ = onGroundDrop?(item.serial,amount,windowPoint)
            cancelDrag(); return
        }
        let automatic = destination == NSPoint(x:0xFFFF,y:0xFFFF)
        let x = automatic ? 0xFFFF : max(0,Int((destination.x-grabOffset.x).rounded()))
        let y = automatic ? 0xFFFF : max(0,Int((destination.y-grabOffset.y).rounded()))
        onMove?(item.serial,amount,x,y,target)
        cancelDrag()
    }
    private func hit(at point: NSPoint, excluding: UInt32? = nil) -> ContainerItem? {
        for item in items.reversed() where item.serial != excluding {
            guard let sprite = try? assets.sprite(item.displayGraphic + 0x4000) else { continue }
            let x = Int(point.x) - item.x, y = Int(point.y) - item.y
            if x >= 0, y >= 0, x < sprite.width, y < sprite.height, sprite.rgba[(y * sprite.width + x) * 4 + 3] != 0 { return item }
        }
        return nil
    }
    var items: [ContainerItem] = []
    var onUse: ((UInt32) -> Void)?
    var onSelect: ((String) -> Void)?
    override var isFlipped: Bool { true }
    init(assets: ClientAssets, background: Sprite?, serial: UInt32) { self.serial = serial; self.assets = assets; self.background = background; super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 260)) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        if let background { drawSprite(background, at: .zero) }
        else { NSColor.darkGray.setFill(); bounds.fill() }
        for item in items {
            do {
                guard let sprite = try assets.sprite(item.displayGraphic + 0x4000),
                      stride(from: 3, to: sprite.rgba.count, by: 4).contains(where: { sprite.rgba[$0] != 0 }) else {
                    ("?" as NSString).draw(at: NSPoint(x: item.x, y: item.y), withAttributes: [.foregroundColor: NSColor.white])
                    continue
                }
                var pixels = sprite.rgba
                if let hue = try assets.huePalette(item.hue, art: item.graphic + 0x4000) {
                    for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i+3] != 0 {
                        let c = hue.color(red: pixels[i], green: pixels[i+1], blue: pixels[i+2])
                        pixels[i] = c.0; pixels[i+1] = c.1; pixels[i+2] = c.2
                    }
                }
                guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                      let image = CGImage(width: sprite.width, height: sprite.height, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: sprite.width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { continue }
                NSGraphicsContext.current?.imageInterpolation = .none
                NSImage(cgImage: image, size: NSSize(width: sprite.width, height: sprite.height)).draw(
                    in: NSRect(x: item.x, y: item.y, width: sprite.width, height: sprite.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } catch { Telemetry.shared.record("container_render_error") }
        }
    }
    private func drawSprite(_ sprite: Sprite, at point: NSPoint) {
        guard let provider = CGDataProvider(data: Data(sprite.rgba) as CFData),
              let image = CGImage(width: sprite.width, height: sprite.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: sprite.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: image, size: NSSize(width: sprite.width, height: sprite.height)).draw(
            in: NSRect(origin: point, size: NSSize(width: sprite.width, height: sprite.height)),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if choosing { return }
        if chosenAmount != nil { finishDrop(at: point); return }
        if closeArea?.contains(point) == true { closing = true; return }
        candidate = hit(at: point); origin = point; pointer = point
        guard let item = candidate else { superview?.mouseDown(with:event); return }
        if onTarget?(item.serial) == true { cancelDrag(); return }
        grabOffset = NSPoint(x: point.x - CGFloat(item.x), y: point.y - CGFloat(item.y))
        let name = (try? assets.itemName(graphic: item.graphic)) ?? "Item"
        let stackable = (try? assets.isStackable(graphic: item.graphic)) == true
        onSelect?(stackable && item.amount > 1 ? "\(name) × \(item.amount)" : name)
        Telemetry.shared.record("container_item_clicked", ["serial": item.serial, "graphic": item.graphic, "clicks": event.clickCount])
        if event.clickCount == 2 { onUse?(item.serial); cancelDrag() }
    }
}

@MainActor
final class ItemDragPreview: NSView {
    var sprite: Sprite?
    var destination = NSRect.zero
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let sprite, let provider = CGDataProvider(data: Data(sprite.rgba) as CFData),
              let image = CGImage(width: sprite.width, height: sprite.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: sprite.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: image, size: NSSize(width: sprite.width, height: sprite.height)).draw(
            in: destination, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
