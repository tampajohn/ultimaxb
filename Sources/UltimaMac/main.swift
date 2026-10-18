import AppKit
import UOCore

struct Options {
    var client = "uo1998-client"
    var output: String?
    var previewBody: Int?
    var previewZ: Int?
    var previewEquipment = false
    var x = 1435, y = 1695
    var statics = true
    var legacyTerrain = false
    var help = false
    var connect = false
    var debugCamera = false
    var sampleEquipment: [EquippedItem] {
        guard previewEquipment else { return [] }
        return [(0x1517, 5, 33), (0x152E, 4, 95), (0x170B, 3, 0), (0x203C, 11, 1109)].enumerated().map {
            EquippedItem(serial: UInt32(0x40000001 + $0.offset), graphic: $0.element.0,
                         layer: UInt8($0.element.1), owner: 1, hue: $0.element.2)
        }
    }
    init(_ arguments: [String]) throws {
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            if arg == "--help" || arg == "-h" { help = true }
            else if arg == "--preview-equipment" { previewEquipment = true }
            else if arg == "--debug-camera" { debugCamera = true }
            else if arg == "--connect" { connect = true }
            else if arg == "--land-only" { statics = false }
            else if arg == "--legacy-terrain" { legacyTerrain = true }
            else if ["--client", "--render", "--x", "--y", "--preview-body", "--preview-z"].contains(arg) {
                i += 1
                guard i < arguments.count else { throw AssetError("Missing value for \(arg)") }
                let value = arguments[i]
                switch arg {
                case "--client": client = value
                case "--render": output = value
                default:
                    guard let number = Int(value) else { throw AssetError("Invalid coordinate: \(value)") }
                    if arg == "--preview-z" { previewZ = number }
                    else if arg == "--preview-body" { previewBody = number }
                    else if arg == "--x" { x = number } else { y = number }
                }
            } else { throw AssetError("Unknown argument: \(arg)") }
            i += 1
        }
    }
}

@MainActor
final class WorldView: NSView {
    let assets: ClientAssets
    private lazy var classicCursor = ClassicCursor(assets: assets)
    var cx: Int, cy: Int
    var showStatics: Bool
    let legacyTerrain: Bool
    var groundObjects: [GroundItem] = []
    var onUse: ((UInt32) -> Void)?
    var onInspect: ((UInt32) -> Void)?
    var onPickup: ((GroundItem) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var hovered: GroundItem?
    private var hoverRestPoint = NSPoint.zero
    private var hoverRestAt: TimeInterval = 0
    private var hoverInspected: UInt32?
    var overheadSpeech = OverheadSpeech()
    func showLabel(_ message: SpeechMessage) {
        overheadSpeech.append(message,at:ProcessInfo.processInfo.systemUptime)
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; hoverInspected = nil; needsDisplay = true }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil), scale = imageRect.width / 960
        let previous = hovered?.serial
        hovered = imageRect.contains(point) ? try? WorldHitTest.groundItem(assets: assets, items: groundObjects, camera: displayedCamera, screenX: (point.x-imageRect.minX)/scale, screenY: (point.y-imageRect.minY)/scale) : nil
        if previous != hovered?.serial {
            hoverInspected = nil; hoverRestAt = ProcessInfo.processInfo.systemUptime; hoverRestPoint = point
        } else if hypot(point.x-hoverRestPoint.x, point.y-hoverRestPoint.y) > 3 {
            hoverRestAt = ProcessInfo.processInfo.systemUptime; hoverRestPoint = point
        }
        needsDisplay = true
    }
    var lighting = WorldLighting() { didSet { if lighting != oldValue { refresh() } } }
    var targeting = false { didSet { window?.invalidateCursorRects(for: self); needsDisplay = true } }
    var onTarget: ((TargetSelection?) -> Void)?
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(imageRect, cursor: classicCursor.cursor(war: player.map { $0.flags & 0x40 != 0 } ?? false, targeting: targeting))
    }
    var onChat: (() -> Void)?
    private var lastCeiling: Int?
    private var displayedCamera = WorldCamera(x: 0, y: 0)
    private var dragged = false
    private var groundDrag: GroundItem?
    private var groundPreview: ItemDragPreview?
    var onGroundDrop: ((GroundItem, NSPoint) -> Void)?
    var groundItems: [WorldTile] = []
    var multiTiles: [WorldTile] = []
    var mobiles: [WorldMobile] = []
    var equipment: [EquippedItem] = []
    var player: WorldMobile?
    var followPlayer = true
    var debugCamera = false
    var onUseEquippedTool: (() -> Void)?
    var walkRoute:[WalkPoint] = []
    var combatTarget: UInt32?
    var onWarMode: (() -> Void)?
    var onAttack: ((UInt32) -> Void)?
    var onSpellbook: (() -> Void)?
    var onMap: (() -> Void)?
    var onJournal: (() -> Void)?
    var onSkills: (() -> Void)?
    var onCharacter: (() -> Void)?
    var onBackpack: (() -> Void)?
    var onMovementTick: (() -> Void)?
    var onWalkTo: ((TargetSelection,UInt32?,Bool) -> Void)?
    var onCancelRoute: (() -> Void)?
    var onMove: ((UInt8) -> Void)?
    private var movementKeys = MovementKeys()
    private(set) var running = false
    private var runMode = RunMode()
    var chatting = false { didSet { updateRunMode(NSEvent.modifierFlags) } }
    private func updateRunMode(_ flags: NSEvent.ModifierFlags) {
        runMode.update(capsLock: flags.contains(.capsLock), chatting: chatting)
        running = runMode.running(shift: flags.contains(.shift))
    }
    private var heldDirection: UInt8? {
        movementKeys.direction.map { $0 | (running ? 0x80 : 0) }
    }
    private var rightPoint: NSPoint?
    override func resignFirstResponder() -> Bool {
        movementKeys.clear(); rightPoint = nil
        return super.resignFirstResponder()
    }
    private var motion = MobileMotion()
    private var animationTimer: Timer?
    private var wasAnimating = false
    func updateMobiles(_ values: [WorldMobile]) {
        mobiles = values
        motion.update(values, at: ProcessInfo.processInfo.systemUptime, playerSerial: player?.serial)
        wasAnimating = motion.isAnimating(at: ProcessInfo.processInfo.systemUptime)
        refresh()
    }
    func playAnimation(_ command:MobileAction) {
        guard let mobile = mobiles.first(where: { $0.serial == command.serial }) else { return }
        do {
            guard let frames = try assets.animations?.frameCount(body:mobile.body,direction:mobile.direction,action:command.action) else {
                Telemetry.shared.record("animation_asset_missing",["body":mobile.body,"action":command.action]); return
            }
            motion.play(command,frames:frames,at:ProcessInfo.processInfo.systemUptime)
            wasAnimating = true; refresh()
        } catch { Telemetry.shared.record("animation_decode_error",["body":mobile.body,"action":command.action]) }
    }
    private func animate() {
        if let window, window.isKeyWindow {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let hit = hitTest(superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil) ?? window.mouseLocationOutsideOfEventStream)
            if imageRect.contains(point), hit === self || groundPreview != nil {
                let direction = rightPoint.map { point in
                    (Int((atan2(point.y-imageRect.midY, point.x-imageRect.midX) / (.pi/4)).rounded())+9)%8
                }
                classicCursor.cursor(war: player.map { $0.flags & 0x40 != 0 } ?? false,
                    targeting: targeting, pickup: groundPreview != nil || (hovered != nil && NSEvent.modifierFlags.contains(.shift)), direction: direction).set()
            }
        }
        if !targeting, groundDrag == nil, window?.isKeyWindow == true,
           let hovered, hoverInspected != hovered.serial,
           ProcessInfo.processInfo.systemUptime-hoverRestAt >= 0.5,
           let window, let hit = hitTest(superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil) ?? window.mouseLocationOutsideOfEventStream), hit === self {
            hoverInspected = hovered.serial
            onInspect?(hovered.serial)
            Telemetry.shared.record("hover_inspect", ["serial": hovered.serial, "graphic": hovered.graphic])
        }
        let priorSpeechCount = overheadSpeech.entries.count
        overheadSpeech.expire(at:ProcessInfo.processInfo.systemUptime)
        if overheadSpeech.entries.count != priorSpeechCount { needsDisplay = true }
        if window?.isKeyWindow != true { movementKeys.clear(); rightPoint = nil }
        // Responder changes can swallow keyUp/mouseUp. Reconcile tracked movement
        // inputs with physical state; never poll or log unrelated typing.
        for key in movementKeys.keyCodes where !CGEventSource.keyState(.combinedSessionState, key: key) {
            movementKeys.release(key)
            Telemetry.shared.record("movement_release_recovered", ["key_code": key])
        }
        if NSEvent.pressedMouseButtons & 2 == 0 { rightPoint = nil }
        updateRunMode(NSEvent.modifierFlags)
        if window?.isKeyWindow == true, window?.firstResponder === self, player != nil {
            if let heldDirection { onMove?(heldDirection) }
            else if let point = rightPoint {
                let pose = player.flatMap { motion.presentations(at: ProcessInfo.processInfo.systemUptime)[$0.serial] }
                let px = pose?.x ?? Double(player?.x ?? cx), py = pose?.y ?? Double(player?.y ?? cy)
                let pz = pose?.z ?? Double(player?.z ?? 0)
                let dx = px - displayedCamera.x, dy = py - displayedCamera.y
                let scale = imageRect.width / 960
                let center = NSPoint(x: imageRect.minX + (480 + (dx-dy)*22)*scale,
                                     y: imageRect.minY + (360 + (dx+dy)*22 - pz*4 + 22)*scale)
                let angle = atan2(point.y - center.y, point.x - center.x)
                let direction = UInt8((Int((angle / (.pi / 4)).rounded()) + 1 + 8) % 8)
                onMove?(direction | (running ? 0x80 : 0))
            }
        }

        onMovementTick?()
        let active = motion.isAnimating(at: ProcessInfo.processInfo.systemUptime)
        if active || wasAnimating { refresh() }
        wasAnimating = active
    }
    var frameImage: CGImage?
    var status = ""
    var dragOrigin: NSPoint?
    var dragCenter = (0, 0)
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(assets: ClientAssets, options: Options) {
        self.assets = assets
        cx = options.x; cy = options.y; showStatics = options.statics
        legacyTerrain = options.legacyTerrain
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 760))
        if let body = options.previewBody {
            mobiles = [WorldMobile(serial: 1, body: body, x: cx, y: cy, z: options.previewZ ?? (try? assets.elevation(x: cx, y: cy)) ?? 0)]
        }
        equipment = options.sampleEquipment
        setAccessibilityLabel("Ultima Online world viewer")
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.animate() }
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refresh() {
        cx = min(assets.width - 1, max(0, cx))
        cy = min(assets.height - 1, max(0, cy))
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let presentations = motion.presentations(at: ProcessInfo.processInfo.systemUptime)
            let camera = followPlayer ? player.map { player in
                let pose = presentations[player.serial]
                return WorldCamera(x: pose?.x ?? Double(player.x), y: pose?.y ?? Double(player.y))
            } : nil
            let visibility = try player.map { try WorldVisibility.around(player: $0, assets: assets, additionalTiles: groundItems) } ?? WorldVisibility()
            if visibility.ceiling != lastCeiling {
                Telemetry.shared.record("visibility_ceiling", ["z": visibility.ceiling as Any? ?? NSNull()])
                lastCeiling = visibility.ceiling
            }
            displayedCamera = camera ?? WorldCamera(x: Double(cx), y: Double(cy))
            let frame = try WorldRenderer.render(assets, x: cx, y: cy, statics: showStatics, legacyTerrain: legacyTerrain, visibility: visibility, camera: camera, groundItems: groundItems, mobiles: mobiles, equipment: equipment, mobilePresentations: presentations, lighting:lighting)
            let provider = CGDataProvider(data: Data(frame.rgba) as CFData)!
            frameImage = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            status = "\(cx), \(cy)  ·  \(frame.landCount) land / \(frame.staticCount) statics  ·  " +
                "\(frame.missingCount) missing  ·  \(ms) ms  ·  cache \(assets.cacheBytes / 1024) KiB"
        } catch {
            frameImage = nil
            Telemetry.shared.record("render_error", ["x": cx, "y": cy, "error": String(describing: error)])
            status = "Cannot render \(cx), \(cy): \(error)"
        }
        needsDisplay = true
    }

    var sidebar: PlaySidebar?
    var sidebarWidth: CGFloat { sidebar?.isHidden == false ? 280 : 0 }
    override func layout() {
        super.layout()
        sidebar?.frame = NSRect(x:0,y:0,width:280,height:max(1,bounds.height-62))
        for chat in subviews.compactMap({ $0 as? ChatPanel }) {
            chat.frame.origin = NSPoint(x:imageRect.minX+12,y:max(0,bounds.height-195))
            chat.frame.size.width = min(540,max(100,imageRect.width-24))
        }
        window?.invalidateCursorRects(for:self)
        needsDisplay = true
    }
    var imageRect: NSRect {
        let available = max(1,bounds.width-sidebarWidth)
        let scale = max(0.01, min(available / 960, max(1, bounds.height - 62) / 720))
        return NSRect(x: sidebarWidth + (available - 960 * scale) / 2, y: 0, width: 960 * scale, height: 720 * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.10, alpha: 1).setFill()
        bounds.fill()
        if let frameImage {
            let image = NSImage(cgImage: frameImage, size: NSSize(width: 960, height: 720))
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
        drawWalkRoute()
        drawObjectFeedback()
        if targeting {
            ("Select a target — T targets yourself · Escape cancels" as NSString).draw(at: NSPoint(x: imageRect.minX + 16, y: 16),
                withAttributes: [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black])
        }
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.lightGray]
        (status as NSString).draw(at: NSPoint(x: 12, y: bounds.height - 46), withAttributes: attrs)
        ((player == nil ? "Drag / arrows: pan   T: statics   R: Britain   Command-L: login" : "Arrows: walk / combine for diagonals   Shift/Caps: run   Right-hold: move   Space: use   U: equipped tool   P: character   K: skills   J: journal   S: spells   M: map   B: backpack   H: recenter   Enter: chat   Command-L: connection") as NSString)
            .draw(at: NSPoint(x: 12, y: bounds.height - 25), withAttributes: attrs)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { if targeting { onTarget?(nil) }; onCancelRoute?(); return }
        if event.keyCode == 36, player != nil {
            movementKeys.clear(); rightPoint = nil
            chatting = true; onChat?(); return
        }
        let step = event.modifierFlags.contains(.shift) ? 4 : 1
        let key = event.charactersIgnoringModifiers?.lowercased()
        if let player {
            if targeting, key == "t" {
                if !event.isARepeat {
                    onTarget?(TargetSelection(serial:player.serial,x:player.x,y:player.y,z:player.z,graphic:player.body))
                }
                return
            }
            if key == " " {
                if !event.isARepeat {
                    do {
                        if let item = try WorldInteraction.facingItem(player: player, items: groundObjects, assets: assets) {
                            Telemetry.shared.record("space_use", ["serial": item.serial, "graphic": item.graphic])
                            onUse?(item.serial)
                        } else { Telemetry.shared.record("space_no_object") }
                    } catch { Telemetry.shared.record("space_hit_error") }
                }
                return
            }
            let direction: UInt8?
            switch (event.keyCode, key) {
            case (123, _): direction = 5
            case (124, _): direction = 1
            case (125, _): direction = 3
            case (126, _): direction = 7
            default: direction = nil
            }
            if let direction {
                updateRunMode(event.modifierFlags)
                if !event.isARepeat { Telemetry.shared.record("movement_key", ["direction": direction, "key_code": event.keyCode, "run": running]) }
                movementKeys.press(event.keyCode, direction: direction)
                updateRunMode(event.modifierFlags)
                return
            }
            if key == "a" { if !event.isARepeat && !chatting { onWarMode?() }; return }
            if key == "u" { if !event.isARepeat && !chatting { onUseEquippedTool?() }; return }
            if key == "s" { if !event.isARepeat { onSpellbook?() }; return }
            if key == "m" { if !event.isARepeat { onMap?() }; return }
            if key == "j" { if !event.isARepeat { onJournal?() }; return }
            if key == "k" { if !event.isARepeat { onSkills?() }; return }
            if key == "p" { if !event.isARepeat { onCharacter?() }; return }
            if key == "b" { if !event.isARepeat { onBackpack?() }; return }
            if event.keyCode == 115 || key == "h" { followPlayer = true; cx = player.x; cy = player.y; refresh(); return }
        }
        guard player == nil || debugCamera else { return }
        switch (event.keyCode, key) {
        case (123, _): cx -= step; cy += step
        case (124, _): cx += step; cy -= step
        case (125, _): cx += step; cy += step
        case (126, _): cx -= step; cy -= step
        case (_, "t"): showStatics.toggle()
        case (_, "r"): cx = 1435; cy = 1695
        default: super.keyDown(with: event); return
        }
        refresh()
    }

    override func keyUp(with event: NSEvent) {
        if movementKeys.release(event.keyCode) { Telemetry.shared.record("movement_key_released", ["key_code": event.keyCode]) }
    }
    override func flagsChanged(with event: NSEvent) { updateRunMode(event.modifierFlags) }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        updateRunMode(event.modifierFlags)
        rightPoint = convert(event.locationInWindow, from: nil)
    }
    override func rightMouseDragged(with event: NSEvent) { rightPoint = convert(event.locationInWindow, from: nil) }
    override func rightMouseUp(with event: NSEvent) { rightPoint = nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragged = false
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragCenter = (cx, cy)
        let point = convert(event.locationInWindow, from: nil), scale = imageRect.width/960
        groundDrag = !targeting && imageRect.contains(point) ? try? WorldHitTest.groundItem(assets: assets, items: groundObjects, camera: displayedCamera, screenX: (point.x-imageRect.minX)/scale, screenY: (point.y-imageRect.minY)/scale) : nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - origin.x, point.y - origin.y) > 4 { dragged = true }
        if dragged, let item = groundDrag, let sprite = try? assets.sprite(item.graphic+0x4000) {
            if groundPreview == nil {
                let preview = ItemDragPreview(frame: bounds); preview.sprite = sprite
                preview.autoresizingMask = [.width,.height]; addSubview(preview, positioned: .above, relativeTo: nil); groundPreview = preview
            }
            let scale = imageRect.width/960
            groundPreview?.destination = NSRect(x: point.x-Double(sprite.width)*scale/2, y: point.y-Double(sprite.height)*scale/2, width: Double(sprite.width)*scale, height: Double(sprite.height)*scale)
            groundPreview?.needsDisplay = true
            return
        }
        guard player == nil || debugCamera else { return }
        let scale = imageRect.width / 960
        let dx = (point.x - origin.x) / scale, dy = (point.y - origin.y) / scale
        let newX = dragCenter.0 - Int(((dx + dy) / 44).rounded())
        let newY = dragCenter.1 - Int(((dy - dx) / 44).rounded())
        if cx != newX || cy != newY { followPlayer = false; cx = newX; cy = newY; refresh() }
    }
    private func drawWalkRoute() {
        guard let player, !walkRoute.isEmpty else { return }
        let scale = imageRect.width/960
        func project(_ x:Double,_ y:Double,_ z:Double)->NSPoint {
            NSPoint(x:imageRect.minX+(480+(x-y-displayedCamera.x+displayedCamera.y)*22)*scale,
                    y:imageRect.minY+(360+(x+y-displayedCamera.x-displayedCamera.y)*22-z*4+22)*scale)
        }
        let pose = motion.presentations(at:ProcessInfo.processInfo.systemUptime)[player.serial]
        let path = NSBezierPath()
        path.move(to:project(pose?.x ?? Double(player.x),pose?.y ?? Double(player.y),pose?.z ?? Double(player.z)))
        for point in walkRoute { path.line(to:project(Double(point.x),Double(point.y),Double(point.z))) }
        NSGraphicsContext.saveGraphicsState(); imageRect.clip()
        let dash:[CGFloat] = [1,7]
        path.setLineDash(dash,count:dash.count,phase:0); path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(0.65).setStroke(); path.lineWidth = 5; path.stroke()
        NSColor.systemMint.setStroke(); path.lineWidth = 3; path.stroke()
        if let goal = walkRoute.last {
            let point = project(Double(goal.x),Double(goal.y),Double(goal.z))
            let marker = NSBezierPath(ovalIn:NSRect(x:point.x-6,y:point.y-4,width:12,height:8))
            marker.lineWidth = 2; marker.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawObjectFeedback() {
        let scale = imageRect.width / 960
        if let serial = combatTarget, let mobile = mobiles.first(where: { $0.serial == serial }) {
            let pose = motion.presentations(at:ProcessInfo.processInfo.systemUptime)[serial]
            let x = pose?.x ?? Double(mobile.x), y = pose?.y ?? Double(mobile.y), z = pose?.z ?? Double(mobile.z)
            let sx = imageRect.minX + (480+(x-y-displayedCamera.x+displayedCamera.y)*22)*scale
            let sy = imageRect.minY + (360+(x+y-displayedCamera.x-displayedCamera.y)*22-z*4+22)*scale
            NSGraphicsContext.saveGraphicsState()
            imageRect.clip()
            NSColor.systemRed.setStroke()
            let marker = NSBezierPath(ovalIn:NSRect(x:sx-16*scale,y:sy-5*scale,width:32*scale,height:10*scale))
            marker.lineWidth = max(1,2*scale); marker.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        if let item = hovered, groundObjects.contains(where: { $0.serial == item.serial }),
           let sprite = try? assets.sprite(item.graphic + 0x4000) {
            let x = (480 + (Double(item.x-item.y)-displayedCamera.x+displayedCamera.y)*22).rounded() - Double(sprite.width/2)
            let y = (360 + (Double(item.x+item.y)-displayedCamera.x-displayedCamera.y)*22-Double(item.z*4)).rounded()+44-Double(sprite.height)
            NSColor.yellow.withAlphaComponent(0.85).setFill()
            func opaque(_ x: Int, _ y: Int) -> Bool {
                x >= 0 && y >= 0 && x < sprite.width && y < sprite.height && sprite.rgba[(y*sprite.width+x)*4+3] != 0
            }
            for sy in 0..<sprite.height {
                for sx in 0..<sprite.width where opaque(sx,sy) && (!opaque(sx-1,sy) || !opaque(sx+1,sy) || !opaque(sx,sy-1) || !opaque(sx,sy+1)) {
                    NSRect(x: imageRect.minX+(x+Double(sx))*scale, y: imageRect.minY+(y+Double(sy))*scale, width: scale, height: scale).fill()
                }
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        overheadSpeech.expire(at:now)
        let poses = motion.presentations(at:now)
        NSGraphicsContext.saveGraphicsState(); imageRect.clip()
        for serial in Set(overheadSpeech.entries.map(\.serial)).sorted() {
            let item = groundObjects.first { $0.serial == serial }
            let mobile = mobiles.first { $0.serial == serial }
            guard let wx = item?.x ?? mobile?.x,let wy = item?.y ?? mobile?.y,let wz = item?.z ?? mobile?.z else { continue }
            let pose = mobile == nil ? nil : poses[serial]
            let px = pose?.x ?? Double(wx), py = pose?.y ?? Double(wy), pz = pose?.z ?? Double(wz)
            let height = item.flatMap { try? assets.sprite($0.graphic+0x4000)?.height } ?? 65
            let x = imageRect.minX+(480+(px-py-displayedCamera.x+displayedCamera.y)*22)*scale
            var y = imageRect.minY+(360+(px+py-displayedCamera.x-displayedCamera.y)*22-pz*4+44-Double(height))*scale-4
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let textWidth = min(240,max(1,imageRect.width-8))
            for entry in overheadSpeech.entries.filter({ $0.serial == serial }).reversed() {
                var color = NSColor.white
                if let palette = try? assets.huePalette(Int(entry.hue)) {
                    let rgb = palette.color(red:255,green:255,blue:255)
                    color = NSColor(calibratedRed:CGFloat(rgb.0)/255,green:CGFloat(rgb.1)/255,blue:CGFloat(rgb.2)/255,alpha:1)
                }
                let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:14),.foregroundColor:color,
                    .backgroundColor:NSColor.black.withAlphaComponent(0.8),.paragraphStyle:style]
                let text = entry.text as NSString
                let size = text.boundingRect(with:NSSize(width:textWidth,height:100),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs).size
                let height = min(100,ceil(size.height))
                y -= height+2
                let left = max(imageRect.minX+4,min(imageRect.maxX-textWidth-4,x-textWidth/2))
                text.draw(with:NSRect(x:left,y:y,width:textWidth,height:height),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func groundDropLocation(windowPoint:NSPoint)->TargetSelection? {
        let point = convert(windowPoint,from:nil)
        guard let player, imageRect.contains(point), hitTest(superview?.convert(windowPoint,from:nil) ?? point) === self else { return nil }
        let scale = imageRect.width/960
        let visibility = (try? WorldVisibility.around(player:player,assets:assets)) ?? WorldVisibility()
        guard let location = try? WorldHitTest.location(assets:assets,camera:displayedCamera,screenX:(point.x-imageRect.minX)/scale,screenY:(point.y-imageRect.minY)/scale,visibility:visibility),
              max(abs(location.x-player.x),abs(location.y-player.y)) <= 2 else { return nil }
        return location
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil; groundDrag = nil; groundPreview?.removeFromSuperview(); groundPreview = nil }
        if dragged, let item = groundDrag { onGroundDrop?(item, event.locationInWindow); return }
        guard !dragged, player != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        let scale = imageRect.width / 960
        do {
            let screenX = (point.x - imageRect.minX) / scale, screenY = (point.y - imageRect.minY) / scale
            if targeting, let mobile = try WorldHitTest.mobile(assets: assets, mobiles: mobiles,
                presentations: motion.presentations(at: ProcessInfo.processInfo.systemUptime), camera: displayedCamera, screenX: screenX, screenY: screenY, equipment:equipment) {
                onTarget?(TargetSelection(serial: mobile.serial, x: mobile.x, y: mobile.y, z: mobile.z, graphic: mobile.body)); return
            }
            if let item = try WorldHitTest.groundItem(assets: assets, items: groundObjects, camera: displayedCamera,
                screenX: (point.x - imageRect.minX) / scale, screenY: (point.y - imageRect.minY) / scale) {
                if targeting {
                    onTarget?(TargetSelection(serial: item.serial, x: item.x, y: item.y, z: item.z, graphic: item.graphic)); return
                }
                if event.clickCount == 1 && event.modifierFlags.contains(.shift) { onPickup?(item); return }
                if event.clickCount == 1 { onInspect?(item.serial) }
                let door = try assets.isDoor(graphic: item.graphic)
                Telemetry.shared.record("world_item_clicked", ["serial": item.serial, "graphic": item.graphic, "door": door, "clicks": event.clickCount])
                // Doors use one click; other world objects retain classic double-click use.
                if door && event.clickCount == 1 {
                    onWalkTo?(TargetSelection(x:item.x,y:item.y,z:item.z,graphic:item.graphic),item.serial,running)
                } else if !door && event.clickCount == 2 { onUse?(item.serial) }
            } else if targeting {
                let visibility = try player.map { try WorldVisibility.around(player: $0, assets: assets, additionalTiles: groundItems) } ?? WorldVisibility()
                if let location = try WorldHitTest.location(assets: assets, camera: displayedCamera, screenX: screenX, screenY: screenY, visibility: visibility) { onTarget?(location) }
            } else if let mobile = try WorldHitTest.mobile(assets: assets, mobiles: mobiles, presentations: motion.presentations(at: ProcessInfo.processInfo.systemUptime), camera: displayedCamera, screenX: screenX, screenY: screenY, equipment:equipment) {
                if event.clickCount == 1 { onInspect?(mobile.serial) }
                if event.clickCount == 2, (player?.flags ?? 0) & 0x40 != 0 { onAttack?(mobile.serial) }
            } else if event.clickCount == 1 {
                let visibility = try player.map { try WorldVisibility.around(player:$0,assets:assets,additionalTiles:groundItems) } ?? WorldVisibility()
                if let location = try WorldHitTest.location(assets:assets,camera:displayedCamera,screenX:screenX,screenY:screenY,visibility:visibility) {
                    onWalkTo?(location,nil,running)
                }
            }
        } catch { Telemetry.shared.record("world_hit_error", ["error": String(describing: error)]) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let audio = GameAudio()
    @objc func toggleSound(_ item:NSMenuItem) {
        audio.enabled.toggle(); item.state = audio.enabled ? .on : .off
        Telemetry.shared.record("sound_setting_changed",["enabled":audio.enabled])
    }
    func applicationDidResignActive(_ notification:Notification) { audio.pause() }
    func applicationDidBecomeActive(_ notification:Notification) { audio.resume() }
    @objc func toggleMusic(_ item:NSMenuItem) {
        audio.musicEnabled.toggle(); item.state = audio.musicEnabled ? .on : .off
        Telemetry.shared.record("music_setting_changed",["enabled":audio.musicEnabled])
    }

    var loginOverlay: LoginOverlay?
    var characterPanel: CharacterPanel?
    var vendorPanel: VendorPanel?
    var skillsPanel: SkillsPanel?
    private var mapPanel:MapPanel?
    private var deathPanel:DeathPanel?
    private var textPromptPanel:TextPromptPanel?
    private var tradePanel:TradePanel?
    private var huePickerPanel:HuePickerPanel?
    private var serverGumpPanels:[UInt64:ServerGumpPanel] = [:]
    private var serverMenuPanel:ServerMenuPanel?
    private var spellShortcuts:[UInt64:SpellShortcut] = [:]
    private var spellbooks:[UInt32:SpellbookPanel] = [:]
    private func toggleMap() {
        guard let view = worldView, view.player != nil else { return }
        if let mapPanel, mapPanel.superview != nil { mapPanel.removeFromSuperview() }
        else {
            let panel = mapPanel ?? MapPanel(assets:assets); mapPanel = panel
            panel.onTravel = { [weak self] x,y in
                self?.travelOnMap(x:x,y:y)
                self?.window?.makeFirstResponder(self?.worldView)
            }
            panel.update(player:view.player,mobiles:view.mobiles); view.addSubview(panel)
        }
        Telemetry.shared.record("map_toggled",["visible":mapPanel?.superview != nil])
    }
    func showSkills() {
        guard let view = worldView, view.player != nil else { return }
        view.sidebar?.skills.isHidden.toggle()
        loginOverlay?.requestSkills()
        view.window?.makeFirstResponder(view)
    }
    var containerPanels: [UInt32: ContainerPanel] = [:]
    lazy var chatPanel = ChatPanel(assets: assets)
    private var journalPanel:JournalPanel?
    private func showJournal(toggle: Bool = true, scrollEvent: NSEvent? = nil) {
        guard let view = worldView, view.player != nil else { return }
        if let panel = journalPanel, panel.superview != nil {
            if toggle { panel.removeFromSuperview(); view.window?.makeFirstResponder(view) }
            else if let scrollEvent { panel.scrollHistory(with: scrollEvent) }
            return
        }
        let panel = journalPanel ?? JournalPanel(assets:assets)
        panel.update(chatPanel.history)
        panel.onClose = { [weak self] in self?.journalPanel?.removeFromSuperview(); self?.worldView?.window?.makeFirstResponder(self?.worldView) }
        journalPanel = panel; view.addSubview(panel)
        if let scrollEvent { panel.scrollHistory(with: scrollEvent) }
        Telemetry.shared.record("journal_opened",["lines":chatPanel.history.lines.count])
    }
    func showCharacter() {
        guard let view = worldView, view.player != nil else { return }
        if let panel = characterPanel { panel.removeFromSuperview(); characterPanel = nil; view.window?.makeFirstResponder(view); return }
        let panel = CharacterPanel(assets: assets)
        panel.frame.origin.x = max(12, view.bounds.width - panel.frame.width - 16)
        panel.update(player: view.player, equipment: view.equipment)
        panel.setName(loginOverlay?.characterDisplayName ?? "")
        panel.updateStatus(loginOverlay?.characterStatus)
        loginOverlay?.requestStatus()
        panel.onOptions = { [weak self] in self?.showLogin() }
        panel.onLogout = { [weak self] in self?.loginOverlay?.logout() }
        panel.onJournal = { [weak self] in self?.showJournal() }
        panel.onWarMode = { [weak self] in self?.loginOverlay?.toggleWarMode() }
        panel.onSkills = { [weak self] in self?.showSkills() }
        panel.onClose = { [weak self] in self?.showCharacter() }
        panel.onTarget = { [weak self] in self?.loginOverlay?.targetPaperdoll(serial:$0) ?? false }
        panel.onUseEquipment = { [weak self] in self?.loginOverlay?.use(serial: $0) }
        panel.onDropEquipment = { [weak self, weak view] item, point in
            guard let self, let view else { return }
            let inventoryItem = ContainerItem(serial:item.serial,graphic:item.graphic,amount:1,x:0,y:0,container:0,hue:item.hue)
            let destination = CharacterPanel.destination(in:view,windowPoint:point,item:inventoryItem) ?? ContainerPanel.destination(in:view,windowPoint:point,item:inventoryItem)
            if let (target,position) = destination {
                guard target != view.player?.serial else { return }
                self.loginOverlay?.moveItem(serial:item.serial,amount:1,x:Int(position.x),y:Int(position.y),target:target)
            } else if let location = view.groundDropLocation(windowPoint:point) {
                self.loginOverlay?.moveItem(serial:item.serial,amount:1,x:location.x,y:location.y,target:0xFFFFFFFF,z:location.z)
            } else {
                Telemetry.shared.record("paperdoll_drop_no_destination",["serial":item.serial])
                self.chatPanel.append("Drop onto the backpack icon, an open bag, or nearby ground.")
            }
        }
        panel.onRemoveEquipment = { [weak self] in self?.loginOverlay?.removeEquipment(serial: $0) }
        panel.onBackpack = { [weak self] in self?.loginOverlay?.openBackpack() }
        view.addSubview(panel)
        characterPanel = panel
        Telemetry.shared.record("character_panel_opened")
    }
    var worldView: WorldView?
    @objc func showLogin() {
        if loginOverlay == nil {
            let panel = LoginOverlay(assets: assets)
            panel.onWorldEntry = { [weak self] entry in
                guard let self, let view = self.worldView,
                      (0..<self.assets.width).contains(entry.x),
                      (0..<self.assets.height).contains(entry.y) else { return }
                view.followPlayer = true
                view.cx = entry.x; view.cy = entry.y
                view.refresh()
            }
            panel.onContainerOpened = { [weak self, weak panel] container in
                guard let self, let view = self.worldView else { return }
                if let existing = self.containerPanels[container.serial] {
                    existing.removeFromSuperview(); view.addSubview(existing); return
                }
                if self.containerPanels.count >= 8,
                   let oldest = view.subviews.compactMap({ $0 as? ContainerPanel }).first {
                    oldest.removeFromSuperview(); self.containerPanels.removeValue(forKey: oldest.serial)
                }
                let bag = ContainerPanel(container: container, assets: self.assets)
                bag.onGroundDrop = { [weak view, weak panel] serial, amount, point in
                    guard let location = view?.groundDropLocation(windowPoint:point) else { return false }
                    panel?.moveItem(serial:serial,amount:amount,x:location.x,y:location.y,target:0xFFFFFFFF,z:location.z)
                    return true
                }
                bag.onMove = { [weak self, weak panel] serial, amount, x, y, target in
                    if target == self?.worldView?.player?.serial {
                        panel?.equipItemFromInventory(serial: serial)
                    } else { panel?.moveItem(serial: serial, amount: amount, x: x, y: y, target: target) }
                }
                bag.frame.origin = NSPoint(x: min(CGFloat(self.containerPanels.count % 2) * (bag.frame.width + 12) + 12, max(0, view.bounds.width - bag.frame.width)),
                                           y: 20 + CGFloat(self.containerPanels.count / 2) * 40)
                bag.resolveDrop = { [weak view] point, item in
                    guard let view else { return nil }
                    return CharacterPanel.destination(in:view,windowPoint:point,item:item) ?? ContainerPanel.destination(in:view,windowPoint:point,item:item)
                }
                bag.onTarget = { [weak panel] serial in
                    guard panel?.targeting == true else { return false }
                    panel?.targetInventory(serial: serial); return true
                }
                bag.onQuickPickup = { [weak panel] serial, amount in panel?.pickupToBackpack(serial: serial, amount: amount) }
                bag.onUse = { [weak panel] in panel?.use(serial: $0) }
                bag.onClose = { [weak self] in
                    self?.containerPanels.removeValue(forKey: container.serial)?.removeFromSuperview()
                    if let view = self?.worldView { view.window?.makeFirstResponder(view) }
                }
                view.addSubview(bag); self.containerPanels[container.serial] = bag
                Telemetry.shared.record("container_opened", ["serial": container.serial, "graphic": container.graphic])
            }
            panel.onLighting = { [weak self] in self?.worldView?.lighting = $0 }
            panel.onTargeting = { [weak self] active in
                self?.worldView?.targeting = active
                if active, let view = self?.worldView { view.window?.makeFirstResponder(view) }
            }
            panel.onAnimation = { [weak self] in self?.worldView?.playAnimation($0) }
            worldView?.onUseEquippedTool = { [weak panel] in panel?.useEquippedTool() }
            panel.onApproachToolTarget = { [weak self] request,selection,tool in
                self?.approach(selection,action:.toolTarget(request,selection,tool),running:self?.worldView?.running ?? false)
            }
            worldView?.onTarget = { [weak panel] in panel?.target($0) }
            panel.equipmentLayer = { [weak self] graphic in try? self?.assets.equipmentLayer(graphic: graphic) }
            panel.onVendor = { [weak self, weak panel] serial, offers, selling in
                guard let self, let view = self.worldView else { return }
                self.vendorPanel?.removeFromSuperview()
                let vendor = VendorPanel(serial:serial,offers:offers,assets:self.assets,selling:selling)
                vendor.updateGold(panel?.characterStatus?.gold)
                panel?.requestStatus()
                vendor.onBuy = { [weak panel] in panel?.submitVendorTrade($0) }
                vendor.onClose = { [weak panel] in panel?.closeVendor() }
                view.addSubview(vendor); self.vendorPanel = vendor
            }
            panel.onVendorClosed = { [weak self] in self?.vendorPanel?.removeFromSuperview(); self?.vendorPanel = nil }
            panel.onSkills = { [weak self] in self?.skillsPanel?.update($0) }
            panel.onCombatTarget = { [weak self] target in
                self?.worldView?.combatTarget = target.serial
                self?.worldView?.needsDisplay = true
                self?.worldView?.sidebar?.updateCombatTarget(target)
            }
            panel.onCharacterStatus = { [weak self] in self?.characterPanel?.updateStatus($0); self?.vendorPanel?.updateGold($0?.gold); self?.worldView?.sidebar?.updateStatus($0) }
            panel.onMusic = { [weak self] id in
                guard let self else { return }
                self.audio.playMusic(id,directory:URL(fileURLWithPath:self.options.client))
            }
            panel.onSound = { [weak self] sound in
                guard let self else { return }
                self.audio.play(sound,assets:self.assets,listener:self.worldView?.player)
            }
            panel.onSpeech = { [weak self] message in
                self?.worldView?.showLabel(message)
                self?.chatPanel.append(message.name.isEmpty ? message.text : "\(message.name): \(message.text)")
            }
            chatPanel.onSend = { [weak panel] text in panel?.say(text) ?? nil }
            chatPanel.onDismiss = { [weak self] in
                if let view = self?.worldView { view.chatting = false; view.window?.makeFirstResponder(view) }
            }
            if let view = worldView, chatPanel.superview == nil {
                chatPanel.frame.origin = NSPoint(x: 12, y: max(0, view.bounds.height - 195))
                chatPanel.autoresizingMask = [.minYMargin]
                view.addSubview(chatPanel)
            }
            worldView?.onChat = { [weak self] in self?.chatPanel.begin() }
            panel.onInventoryMessage = { [weak self] message in self?.containerPanels.values.forEach { $0.showMessage(message) }; if !["Moving item…", "Equipping item…", "Moving equipment to backpack…", "Inventory updated. Drag to move; drag a stack to split it."].contains(message) { self?.chatPanel.append(message) } }
            panel.onContainerItems = { [weak self] items in
                self?.containerPanels.values.forEach { $0.update(items) }
                self?.spellbooks.values.forEach { $0.update(items) }
            }
            panel.onDeath = { [weak self, weak panel] state in
                guard let self else { return }
                if state.phase == .alive || state.phase == .ghost {
                    self.deathPanel?.removeFromSuperview(); self.deathPanel = nil
                    return
                }
                guard let view = self.worldView else { return }
                let display = self.deathPanel ?? DeathPanel(assets:self.assets)
                display.update(state)
                display.onChoice = { [weak panel] resurrect in panel?.respondToDeath(resurrect:resurrect) }
                if display.superview == nil { view.addSubview(display) }
                self.deathPanel = display
            }
            panel.onTextPrompt = { [weak self, weak panel] request in
                guard let self,let view = self.worldView else { return }
                self.textPromptPanel?.removeFromSuperview(); self.textPromptPanel = nil
                guard let request else { view.window?.makeFirstResponder(view); return }
                let display = TextPromptPanel(request:request,assets:self.assets)
                display.frame.origin = NSPoint(x:max(0,(view.bounds.width-display.frame.width)/2),y:max(0,(view.bounds.height-display.frame.height)/2))
                display.onReply = { [weak panel] text,accepted in panel?.respondToPrompt(request,text:text,accepted:accepted) }
                self.textPromptPanel = display; view.addSubview(display)
            }
            panel.onTrade = { [weak self, weak panel] trade in
                guard let self,let view = self.worldView else { return }
                guard let trade else { self.tradePanel?.removeFromSuperview(); self.tradePanel = nil; return }
                if self.tradePanel?.trade.ownContainer != trade.ownContainer { self.tradePanel?.removeFromSuperview(); self.tradePanel = nil }
                let display = self.tradePanel ?? TradePanel(trade:trade,assets:self.assets)
                display.update(trade)
                display.onAccept = { [weak panel] accepted,revision in panel?.acceptTrade(accepted,revision:revision) }
                display.onCancel = { [weak panel] in panel?.cancelTrade() }
                display.onReturn = { [weak panel] item in panel?.pickupToBackpack(serial:item.serial,amount:item.amount) }
                display.onDrop = { [weak view, weak panel] item,point in
                    guard let view,let (target,position) = ContainerPanel.destination(in:view,windowPoint:point,item:item) else { return }
                    panel?.moveItem(serial:item.serial,amount:item.amount,x:Int(position.x),y:Int(position.y),target:target)
                }
                self.tradePanel = display
                if display.superview == nil { view.addSubview(display) }
            }
            panel.onHuePicker = { [weak self, weak panel] request in
                guard let self else { return }
                self.huePickerPanel?.removeFromSuperview(); self.huePickerPanel = nil
                guard let request,let view = self.worldView else { return }
                panel?.cancelRoute()
                let display = HuePickerPanel(request:request,assets:self.assets)
                display.frame.origin = NSPoint(x:max(0,(view.bounds.width-display.frame.width)/2),y:max(0,(view.bounds.height-display.frame.height)/2))
                display.onChoose = { [weak panel] hue in panel?.chooseHue(hue,request:request) }
                self.huePickerPanel = display; view.addSubview(display)
            }
            panel.onServerGump = { [weak self, weak panel] key,definition in
                guard let self else { return }
                self.serverGumpPanels.removeValue(forKey:key)?.removeFromSuperview()
                guard let definition, let view = self.worldView else { return }
                panel?.cancelRoute()
                let display = ServerGumpPanel(definition:definition,assets:self.assets)
                display.frame.origin.x = min(display.frame.origin.x,max(0,view.bounds.width-display.frame.width))
                display.frame.origin.y = min(display.frame.origin.y,max(0,view.bounds.height-display.frame.height))
                display.onReply = { [weak panel] button,switches,entries in
                    panel?.replyToGump(key:key,definition:definition,button:button,switches:switches,entries:entries)
                }
                self.serverGumpPanels[key] = display; view.addSubview(display)
            }
            panel.onServerMenu = { [weak self, weak panel] menu in
                guard let self else { return }
                self.serverMenuPanel?.removeFromSuperview(); self.serverMenuPanel = nil
                guard let menu, let view = self.worldView else { return }
                panel?.cancelRoute()
                let display = ServerMenuPanel(menu:menu,assets:self.assets)
                display.onChoose = { [weak panel] choice in panel?.chooseServerMenu(choice) }
                self.serverMenuPanel = display; view.addSubview(display)
            }
            panel.onSpellbookOpened = { [weak self, weak panel] serial,items in
                guard let self, let view = self.worldView else { return }
                let book = self.spellbooks[serial] ?? SpellbookPanel(serial:serial,assets:self.assets)
                self.spellbooks[serial] = book
                book.update(items)
                book.onCast = { [weak self, weak panel] id in
                    panel?.castSpell(id,book:serial)
                    self?.window?.makeFirstResponder(self?.worldView)
                }
                book.onShortcut = { [weak self,weak panel,weak view] id,point in
                    guard let self,let view else { return }
                    let key = UInt64(serial)<<32 | UInt64(id)
                    let shortcut:SpellShortcut
                    if let existing = self.spellShortcuts[key] { shortcut = existing }
                    else {
                        guard self.spellShortcuts.count<64 else { return }
                        shortcut = SpellShortcut(spell:id,assets:self.assets)
                        shortcut.onCast = { [weak self,weak panel] in
                            panel?.castSpell(id,book:serial)
                            self?.window?.makeFirstResponder(self?.worldView)
                        }
                        shortcut.onClose = { [weak self] in self?.spellShortcuts.removeValue(forKey:key) }
                        self.spellShortcuts[key] = shortcut
                        Telemetry.shared.record("spell_shortcut_created",["id":id,"book":serial])
                    }
                    shortcut.removeFromSuperview(); view.addSubview(shortcut)
                    shortcut.place(at:view.convert(point,from:nil),in:view)
                }
                book.removeFromSuperview(); view.addSubview(book)
            }
            panel.onGroundObjects = { [weak self] items in
                guard let view = self?.worldView else { return }
                view.groundObjects = items
                view.multiTiles = []
                for item in items where item.graphic >= 0x4000 && item.flags & 0x80 == 0 {
                    do {
                        let tiles = try view.assets.multis?.tiles(id: item.graphic-0x4000, x: item.x, y: item.y, z: item.z, hue: item.hue) ?? []
                        view.multiTiles.append(contentsOf: tiles)
                    } catch { Telemetry.shared.record("multi_decode_error", ["graphic": item.graphic, "error": String(describing: error)]) }
                }
            }
            worldView?.onGroundDrop = { [weak self, weak panel] item, point in
                guard let self, let view = self.worldView else { return }
                let inventoryItem = ContainerItem(serial: item.serial, graphic: item.graphic, amount: item.amount, x: 0, y: 0, container: 0, hue: item.hue)
                let paperdollDestination = CharacterPanel.destination(in:view,windowPoint:point,item:inventoryItem)
                if let paperdollDestination, paperdollDestination.0 == view.player?.serial {
                    panel?.equipItemFromInventory(serial:item.serial); return
                }
                let containerDestination = paperdollDestination ?? ContainerPanel.destination(in:view,windowPoint:point,item:inventoryItem)
                let groundDestination = containerDestination == nil ? view.groundDropLocation(windowPoint:point) : nil
                guard containerDestination != nil || groundDestination != nil else { return }
                let target = containerDestination?.0 ?? 0xFFFFFFFF
                let location = containerDestination?.1 ?? NSPoint(x:groundDestination!.x,y:groundDestination!.y)
                let move: (Int) -> Void = { [weak panel] amount in
                    panel?.moveItem(serial: item.serial, amount: amount, x: Int(location.x), y: Int(location.y), target: target, z:groundDestination?.z ?? 0)
                }
                if (try? self.assets.isStackable(graphic: item.graphic)) == true && item.amount > 1 {
                    let quantity = StackQuantityPanel(maximum: min(65535,item.amount), assets: self.assets)
                    quantity.onConfirm = { [weak quantity] amount in move(amount); quantity?.removeFromSuperview() }
                    quantity.onCancel = { [weak quantity] in quantity?.removeFromSuperview() }
                    view.addSubview(quantity)
                } else { move(1) }
            }
            worldView?.onPickup = { [weak self] item in
                guard let self else { return }
                let stackable = (try? self.assets.isStackable(graphic:item.graphic)) == true
                self.approach(TargetSelection(x:item.x,y:item.y,z:item.z,graphic:item.graphic),
                              action:.pickup(item.serial,stackable ? min(65535,max(1,item.amount)) : 1),
                              running:self.worldView?.running ?? false)
            }
            worldView?.onInspect = { [weak panel] in panel?.inspect(serial: $0) }
            worldView?.onUse = { [weak panel] in panel?.use(serial: $0) }
            panel.onGroundItems = { [weak self] tiles in
                guard let view = self?.worldView else { return }
                view.groundItems = tiles + view.multiTiles
                view.refresh()
            }
            panel.onEquipment = { [weak self] equipment in
                self?.worldView?.equipment = equipment
                self?.characterPanel?.update(player: self?.worldView?.player, equipment: equipment)
            }
            panel.onPlayer = { [weak self] player in
                guard let view = self?.worldView else { return }
                let modeChanged = view.player?.flags != player?.flags
                view.player = player
                if self?.mapPanel?.superview != nil { self?.mapPanel?.update(player:player,mobiles:view.mobiles) }
                if modeChanged { self?.characterPanel?.update(player:player,equipment:view.equipment) }
                view.sidebar?.updateMode(war:(player?.flags ?? 0) & 0x40 != 0)
                view.window?.invalidateCursorRects(for:view)
                view.sidebar?.isHidden = player == nil
                view.sidebar?.updateEquipment(view.equipment, player:player?.serial, assets:view.assets)
                if player == nil { self?.audio.stop(); view.sidebar?.updateStatus(nil); self?.skillsPanel?.update(SkillState()) }
                view.needsLayout = true
                if player == nil { self?.worldView?.overheadSpeech = OverheadSpeech(); self?.spellShortcuts.values.forEach { $0.removeFromSuperview() }; self?.spellShortcuts.removeAll(); self?.spellbooks.values.forEach { $0.removeFromSuperview() }; self?.spellbooks.removeAll(); self?.chatPanel.reset(); self?.journalPanel?.removeFromSuperview(); self?.characterPanel?.removeFromSuperview(); self?.characterPanel = nil; self?.containerPanels.values.forEach { $0.removeFromSuperview() }; self?.containerPanels.removeAll() }
                if let player, view.followPlayer, player.x != view.cx || player.y != view.cy {
                    view.cx = player.x; view.cy = player.y; view.refresh()
                }
                view.needsDisplay = true
            }
            panel.predictedElevation = { [weak self] x, y, z in
                guard let self else { return z }
                return (try? self.assets.predictedStepZ(x: x, y: y, fromZ: z)) ?? z
            }
            worldView?.onWarMode = { [weak panel] in panel?.toggleWarMode() }
            worldView?.onAttack = { [weak self] serial in
                guard let self, let mobile = self.worldView?.mobiles.first(where: { $0.serial == serial }) else { return }
                self.approach(TargetSelection(x:mobile.x,y:mobile.y,z:mobile.z,graphic:0),
                              action:.attack(serial),running:self.worldView?.running ?? false)
            }
            worldView?.onSpellbook = { [weak panel] in panel?.openSpellbook() }
            worldView?.onMap = { [weak self] in self?.toggleMap() }
            worldView?.onSkills = { [weak self] in self?.showSkills() }
            worldView?.onCharacter = { [weak self] in self?.showCharacter() }
            worldView?.onBackpack = { [weak panel] in panel?.openBackpack() }
            panel.onWalkRoute = { [weak self] route in self?.worldView?.walkRoute = route; self?.worldView?.needsDisplay = true }
            worldView?.onCancelRoute = { [weak panel] in panel?.cancelRoute() }
            worldView?.onWalkTo = { [weak self] location,door,running in
                self?.approach(location,action:door.map { .use($0) },running:running)
            }
            worldView?.onMovementTick = { [weak self, weak panel] in
                guard let view = self?.worldView else { return }
                panel?.tickMovement(allowRoute:view.window?.isKeyWindow == true && view.window?.firstResponder === view && !view.chatting)
            }
            worldView?.onMove = { [weak self, weak panel] direction in
                if let view = self?.worldView, !view.followPlayer, let player = view.player {
                    view.followPlayer = true; view.cx = player.x; view.cy = player.y; view.refresh()
                    Telemetry.shared.record("camera_follow_resumed")
                }
                panel?.move(direction: direction)
            }
            panel.onMobiles = { [weak self] mobiles in
                guard let view = self?.worldView else { return }
                view.updateMobiles(mobiles)
                if self?.mapPanel?.superview != nil { self?.mapPanel?.update(player:view.player,mobiles:mobiles) }
            }
            panel.onDismiss = { [weak self] in
                guard let view = self?.worldView else { return }
                view.window?.makeFirstResponder(view)
            }
            loginOverlay = panel
        }
        if let worldView { loginOverlay?.show(in: worldView) }
    }
    private func travelOnMap(x:Int,y:Int) {
        guard let view = worldView, let player = view.player, let panel = loginOverlay else { return }
        panel.cancelRoute()
        let planner: (WalkPoint,Set<WalkPoint>)->[WalkPoint]? = { [weak self] start,blocked in
            guard let self, let view = self.worldView,
                  let map = try? NavigationMap(assets:self.assets,center:start,additional:view.groundItems,radius:48) else { return nil }
            return WalkPath.find(from:start,x:x,y:y,segmentLength:32) { point,direction in
                guard let next = map.step(from:point,direction:direction), !blocked.contains(next) else { return nil }
                return next
            }
        }
        let start = WalkPoint(x:player.x,y:player.y,z:player.z)
        guard let route = planner(start,[]) else { chatPanel.append("No clear route toward that map destination."); return }
        view.followPlayer = true
        panel.followRoute(route,action:nil,running:view.running,continuing:true,resolver:planner)
        Telemetry.shared.record("map_travel_requested",["x":x,"y":y,"steps":route.count])
    }
    private func approach(_ location:TargetSelection, action:LoginOverlay.ArrivalAction?, running:Bool) {
        guard let view = worldView, let player = view.player, let panel = loginOverlay else { return }
        panel.cancelRoute()
        let start = WalkPoint(x:player.x,y:player.y,z:player.z)
        guard max(abs(start.x-location.x),abs(start.y-location.y)) <= 24 else {
            chatPanel.append("Choose a closer destination."); return
        }
        do {
            let map = try NavigationMap(assets:assets,center:start,additional:view.groundItems)
            // A mineable cliff face is not a floor to stand on. Reach a neighboring
            // walkable tile without requiring the clicked cliff's elevation.
            let goalZ:Int?
            if case .toolTarget = action { goalZ = nil } else { goalZ = action == nil ? nil : location.z }
            guard let route = WalkPath.find(from:start,x:location.x,y:location.y,adjacent:action != nil,
                                            goalZ:goalZ,
                                            step:{ map.step(from:$0,direction:$1) }) else {
                chatPanel.append("No clear route to that location.")
                Telemetry.shared.record("walk_route_unreachable",["x":location.x,"y":location.y]); return
            }
            view.followPlayer = true
            panel.followRoute(route,action:action,running:running) { [weak self] start,blocked in
                guard let self, let view = self.worldView,
                      let map = try? NavigationMap(assets:self.assets,center:start,additional:view.groundItems) else { return nil }
                return WalkPath.find(from:start,x:location.x,y:location.y,adjacent:action != nil,
                                     goalZ:goalZ) { point,direction in
                    guard let next = map.step(from:point,direction:direction), !blocked.contains(next) else { return nil }
                    return next
                }
            }
        } catch { chatPanel.append("Unable to plan that route."); Telemetry.shared.record("walk_route_error") }
    }
    var window: NSWindow?
    let assets: ClientAssets
    let options: Options
    init(assets: ClientAssets, options: Options) { self.assets = assets; self.options = options }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Telemetry.shared.installClickMonitor()
        let menu = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu()
        let connect = submenu.addItem(withTitle: "Connect…", action: #selector(showLogin), keyEquivalent: "l")
        connect.target = self
        let sound = submenu.addItem(withTitle:"Sound Effects",action:#selector(toggleSound(_:)),keyEquivalent:"")
        sound.target = self; sound.state = audio.enabled ? .on : .off
        let music = submenu.addItem(withTitle:"Music",action:#selector(toggleMusic(_:)),keyEquivalent:"")
        music.target = self; music.state = audio.musicEnabled ? .on : .off
        submenu.addItem(withTitle: "Quit UltimaMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
        let view = WorldView(assets: assets, options: options)
        view.debugCamera = options.debugCamera
        worldView = view
        view.onJournal = { [weak self] in self?.showJournal() }
        chatPanel.onHistoryRequested = { [weak self] event in self?.showJournal(toggle: false, scrollEvent: event) }
        chatPanel.onHistory = { [weak self] history in self?.journalPanel?.update(history) }
        let sidebar = PlaySidebar(definitions: assets.skills)
        sidebar.isHidden = true; view.sidebar = sidebar; skillsPanel = sidebar.skills
        sidebar.skills.onUse = { [weak self] in self?.loginOverlay?.useSkill($0) }
        sidebar.onCommand = { [weak self] command in
            switch command {
            case 0: self?.showCharacter()
            case 1: self?.loginOverlay?.openBackpack()
            case 2: self?.loginOverlay?.useEquippedTool()
            default: self?.loginOverlay?.toggleWarMode()
            }
            self?.window?.makeFirstResponder(self?.worldView)
        }
        view.addSubview(sidebar)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "UltimaMac — World Preview"
        window.subtitle = "Client assets \(assets.reportedVersion) · \(assets.width) × \(assets.height)"
        window.minSize = NSSize(width: 800, height: 640)
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        if options.connect { showLogin() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    if options.help {
        print("""
        UltimaMac — native Swift offline UO world viewer
        swift run -c release UltimaMac [--client DIRECTORY] [--x X --y Y] [--land-only]
        Add --render OUTPUT.bmp to render without opening a window.
        Add --preview-body 400 to place an offline human body at the starting location.
        Add --preview-equipment with --preview-body for sample clothing/hair (offline only).
        Add --debug-camera to allow camera panning during connected play.
        Add --connect to show login in the game window (also available with Command-L).
        Default client: ./uo1998-client; default location: Britain (1435,1695).
        """)
    } else {
        let assets = try ClientAssets(directory: URL(fileURLWithPath: options.client))
        guard (0..<assets.width).contains(options.x), (0..<assets.height).contains(options.y) else {
            throw AssetError("Starting coordinates are outside map0")
        }
        if let output = options.output {
            let start = CFAbsoluteTimeGetCurrent()
            let preview = try options.previewBody.map { body in
                WorldMobile(serial: 1, body: body, x: options.x, y: options.y, z: try options.previewZ ?? assets.elevation(x: options.x, y: options.y))
            }
            let frame = try WorldRenderer.render(assets, x: options.x, y: options.y, statics: options.statics,
                                                 legacyTerrain: options.legacyTerrain, visibility: try preview.map { try WorldVisibility.around(player: $0, assets: assets) } ?? WorldVisibility(), mobiles: preview.map { [$0] } ?? [], equipment: options.sampleEquipment)
            try frame.writeBMP(to: URL(fileURLWithPath: output))
            print("Rendered \(output): \(frame.landCount) land, \(frame.staticCount) statics, \(frame.missingCount) missing, " +
                  "\(frame.huedCount) unapplied hues; \(assets.artOverrideCount) art patches; " +
                  "cache \(assets.cacheBytes) bytes; \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000)) ms")
        } else {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = AppDelegate(assets: assets, options: options)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
    }
} catch {
    FileHandle.standardError.write(Data("UltimaMac: \(error)\nUse --help for usage.\n".utf8))
    exit(1)
}
