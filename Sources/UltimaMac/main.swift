import AppKit
import CoreText
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
    // Preview/debug visibility must never hide scenery during normal play.
    var rendersStatics: Bool { player != nil && !debugCamera || showStatics }
    private var lastRenderDiagnostic: TimeInterval = -.infinity
    let legacyTerrain: Bool
    var effects = WorldEffects()
    var groundObjects: [GroundItem] = []
    var onUse: ((UInt32) -> Void)?
    var onInspect: ((UInt32) -> Void)?
    var onPickup: ((GroundItem) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var hovered: GroundItem?
    private var hoveredMobile:UInt32?
    var onHoverInspect:((UInt32)->Void)?
    private var hoverRestPoint = NSPoint.zero
    private var hoverRestAt: TimeInterval = 0
    private var hoverInspected: UInt32?
    var overheadSpeech = OverheadSpeech()
    private var speechFonts:[UInt32:ClassicText] = [:]
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
    override func mouseExited(with event: NSEvent) { hovered = nil; hoveredMobile = nil; hoverInspected = nil; needsDisplay = true }
    override func mouseMoved(with event: NSEvent) {
        controllerPoint = nil
        let point = convert(event.locationInWindow, from: nil), scale = worldScale
        let previous = hovered?.serial ?? hoveredMobile
        hovered = imageRect.contains(point) ? try? WorldHitTest.groundItem(assets: assets, animationTime:displayedAnimationTime, items: groundObjects, camera: displayedCamera, screenX: (point.x-imageRect.minX)/scale, screenY: (point.y-imageRect.minY)/scale, width:displayedWidth, height:displayedHeight) : nil
        hoveredMobile = nil
        if hovered == nil, imageRect.contains(point) {
            hoveredMobile = (try? WorldHitTest.mobile(assets:assets,mobiles:mobiles,
                presentations:motion.presentations(at:ProcessInfo.processInfo.systemUptime),camera:displayedCamera,
                screenX:(point.x-imageRect.minX)/scale,screenY:(point.y-imageRect.minY)/scale,equipment:equipment, width:displayedWidth, height:displayedHeight))?.serial
        }
        if previous != (hovered?.serial ?? hoveredMobile) {
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
    private var discardMouseUp = false
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
    private let controllerInput = ControllerInput()
    private var controllerPoint: NSPoint?
    private var controllerSampleAt: TimeInterval?
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
    func cancelInteraction() {
        movementKeys.clear(); rightPoint = nil; controllerInput.suspend(); controllerPoint = nil
        dragOrigin = nil; dragged = false; groundDrag = nil; discardMouseUp = true
        groundPreview?.removeFromSuperview(); groundPreview = nil
        needsDisplay = true
    }
    override func resignFirstResponder() -> Bool {
        movementKeys.clear(); rightPoint = nil; controllerInput.suspend(); controllerPoint = nil
        return super.resignFirstResponder()
    }
    private var motion = MobileMotion()
    private var deaths = DeathAnimations()
    func resetDeathAnimations() { deaths = DeathAnimations() }
    func playDeath(_ event:MobileDeath,mobile:WorldMobile,equipment:[EquippedItem]) {
        let action = CorpseArt.deathAction(body:mobile.body,alternate:event.alternate)
        do {
            guard let frames = try assets.animations?.frameCount(body:mobile.body,direction:mobile.direction,action:action),frames > 0 else { return }
            let now = ProcessInfo.processInfo.systemUptime
            deaths.play(event,mobile:mobile,equipment:equipment,pose:motion.presentations(at:now)[mobile.serial],frames:frames,at:now)
            wasAnimating = true
        } catch { Telemetry.shared.record("death_animation_asset_error",["body":mobile.body,"action":action]) }
    }
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
           let serial = hovered?.serial ?? hoveredMobile, hoverInspected != serial,
           ProcessInfo.processInfo.systemUptime-hoverRestAt >= 0.5,
           let window, let hit = hitTest(superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil) ?? window.mouseLocationOutsideOfEventStream), hit === self {
            hoverInspected = serial
            onHoverInspect?(serial)
            Telemetry.shared.record("hover_inspect", ["serial": serial])
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
        let wasConnected = controllerInput.connected
        let controller = controllerInput.poll(enabled: window?.isKeyWindow == true && window?.firstResponder === self && !chatting && player != nil)
        if wasConnected != controllerInput.connected { needsDisplay = true }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.05, max(0, now-(controllerSampleAt ?? now)))
        controllerSampleAt = now
        if !controllerInput.connected || window?.isKeyWindow != true || window?.firstResponder !== self || chatting || player == nil {
            if controllerPoint != nil { controllerPoint = nil; needsDisplay = true }
        } else if controller.cursorX != 0 || controller.cursorY != 0 {
            let prior = controllerPoint ?? NSPoint(x:imageRect.midX,y:imageRect.midY)
            controllerPoint = NSPoint(x:min(imageRect.maxX-1,max(imageRect.minX,prior.x+controller.cursorX*500*elapsed)),
                                      y:min(imageRect.maxY-1,max(imageRect.minY,prior.y+controller.cursorY*500*elapsed)))
            needsDisplay = true
        }
        for action in controller.actions.sorted(by: { $0.rawValue < $1.rawValue }) {
            Telemetry.shared.record("controller_action", ["action": action.rawValue])
            switch action {
            case .use:
                if targeting {
                    let point = controllerPoint ?? NSPoint(x:imageRect.midX,y:imageRect.midY)
                    controllerPoint = point
                    if hitTest(convert(point,to:superview)) === self { clickWorld(at:point,clickCount:1,shift:false) }
                } else { useFacingObject() }
            case .cancel: if targeting { onTarget?(nil) }; onCancelRoute?()
            case .backpack: onBackpack?()
            case .character: onCharacter?()
            case .tool: onUseEquippedTool?()
            }
        }
        if window?.isKeyWindow == true, window?.firstResponder === self, player != nil {
            if let heldDirection { onMove?(heldDirection) }
            else if let direction = controller.direction { onMove?(direction) }
            else if let point = rightPoint {
                let pose = player.flatMap { motion.presentations(at: ProcessInfo.processInfo.systemUptime)[$0.serial] }
                let px = pose?.x ?? Double(player?.x ?? cx), py = pose?.y ?? Double(player?.y ?? cy)
                let pz = pose?.z ?? Double(player?.z ?? 0)
                let dx = px - displayedCamera.x, dy = py - displayedCamera.y
                let scale = worldScale
                let center = NSPoint(x: imageRect.minX + (worldCenterX + (dx-dy)*22)*scale,
                                     y: imageRect.minY + (worldCenterY + (dx+dy)*22 - pz*4 + 22)*scale)
                let angle = atan2(point.y - center.y, point.x - center.x)
                let direction = UInt8((Int((angle / (.pi / 4)).rounded()) + 1 + 8) % 8)
                onMove?(direction | (running ? 0x80 : 0))
            }
        }

        onMovementTick?()
        let active = motion.isAnimating(at: ProcessInfo.processInfo.systemUptime) || effects.count > 0 || deaths.isAnimating
        if active || wasAnimating || (assets.staticAnimations != nil && ProcessInfo.processInfo.systemUptime-displayedAnimationTime >= 0.08) { refresh() }
        wasAnimating = active
    }
    private var displayedAnimationTime:TimeInterval = 0
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
        animationTimer = Timer(timeInterval:1.0/30.0,repeats:true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.animate() }
        }
        if let animationTimer { RunLoop.main.add(animationTimer,forMode:.common) }
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
            let renderTime = ProcessInfo.processInfo.systemUptime
            deaths.expire(at:renderTime)
            let hiddenCorpses = deaths.hiddenCorpses
            let renderGround = groundItems.filter { tile in !(tile.sourceSerial.map { hiddenCorpses.contains($0) } ?? false) }
            let renderMobiles = mobiles.filter { !deaths.hides($0) } + deaths.mobiles
            let renderPoses = presentations.merging(deaths.presentations(at:renderTime),uniquingKeysWith:{ _,death in death })
            let frame = try WorldRenderer.render(assets, x: cx, y: cy, statics: rendersStatics, width:renderSize.width, height:renderSize.height, legacyTerrain: legacyTerrain, visibility: visibility, camera: camera, groundItems: renderGround + effects.tiles(at:renderTime,mobiles:mobiles,items:groundObjects,presentations:presentations), mobiles: renderMobiles, equipment: equipment + deaths.equipment, mobilePresentations: renderPoses, lighting:lighting, animationTime:renderTime, outlinedMobiles:Set(mobiles.filter { $0.serial != player?.serial && ($0.isEnemy || $0.serial == combatTarget) }.map(\.serial)))
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastRenderDiagnostic >= 5 {
                Telemetry.shared.record("render_state", ["x":cx, "y":cy, "statics_enabled":rendersStatics,
                    "preview_statics_enabled":showStatics, "debug_camera":debugCamera,
                    "land_count":frame.landCount, "static_count":frame.staticCount, "missing_count":frame.missingCount,
                    "ceiling":visibility.ceiling as Any? ?? NSNull(),
                    "ceiling_cells":visibility.ceilingCells?.count ?? 0,
                    "terrain_ceiling":visibility.terrainCeiling as Any? ?? NSNull()])
                lastRenderDiagnostic = now
            }
            let provider = CGDataProvider(data: Data(frame.rgba) as CFData)!
            guard let nextImage = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                throw AssetError("Cannot create world frame image")
            }
            // Publish the image and its hit-test coordinates together. A failed
            // refresh keeps the last complete frame instead of flashing black.
            frameImage = nextImage
            displayedCamera = camera ?? WorldCamera(x: Double(cx), y: Double(cy))
            displayedAnimationTime = renderTime
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            status = "\(cx), \(cy)  ·  \(frame.landCount) land / \(frame.staticCount) statics  ·  " +
                "\(frame.missingCount) missing  ·  \(ms) ms  ·  cache \(assets.cacheBytes / 1024) KiB" + (rendersStatics ? "" : "  ·  SCENERY HIDDEN (T)")
        } catch {
            Telemetry.shared.record("render_error", ["x": cx, "y": cy, "error": String(describing: error), "retained_frame": frameImage != nil])
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
        if frameImage?.width != renderSize.width || frameImage?.height != renderSize.height { refresh() }
        needsDisplay = true
    }
    var imageRect: NSRect {
        NSRect(x:sidebarWidth,y:0,width:max(1,bounds.width-sidebarWidth),height:max(1,bounds.height-62))
    }
    private var renderSize: WorldViewport {
        WorldViewport(availableWidth:Double(imageRect.width),availableHeight:Double(imageRect.height))
    }
    private var displayedWidth:Int { frameImage?.width ?? renderSize.width }
    private var displayedHeight:Int { frameImage?.height ?? renderSize.height }
    private var worldScale:CGFloat { imageRect.width / CGFloat(displayedWidth) }
    private var worldCenterX:Double { Double(displayedWidth / 2) }
    private var worldCenterY:Double { Double(displayedHeight / 2) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.10, alpha: 1).setFill()
        bounds.fill()
        if let frameImage {
            let image = NSImage(cgImage: frameImage, size: NSSize(width:frameImage.width,height:frameImage.height))
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
        drawWalkRoute()
        drawObjectFeedback()
        if let point = controllerPoint {
            let cursor = classicCursor.cursor(war:player.map { $0.flags & 0x40 != 0 } ?? false,targeting:targeting)
            NSGraphicsContext.saveGraphicsState(); imageRect.clip()
            cursor.image.draw(in:NSRect(origin:NSPoint(x:point.x-cursor.hotSpot.x,y:point.y-cursor.hotSpot.y),size:cursor.image.size),
                              from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        if targeting {
            ClassicText(assets.fonts,font:3).draw("Select a target - T targets yourself - Escape cancels",at:NSPoint(x:imageRect.minX+16,y:16))
        }
        func debugText(_ text:String,at point:NSPoint) {
            guard let context=NSGraphicsContext.current?.cgContext else { return }
            let attributes:[NSAttributedString.Key:Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Menlo" as CFString,11,nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):NSColor.lightGray.cgColor]
            let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attributes))
            context.saveGState(); context.translateBy(x:point.x,y:point.y+11); context.scaleBy(x:1,y:-1)
            context.textMatrix = .identity; context.textPosition = .zero; CTLineDraw(line,context); context.restoreGState()
        }
        debugText(status + (controllerInput.connected ? "   Controller connected" : ""),at:NSPoint(x:12,y:bounds.height-46))
        debugText(controllerInput.connected && player != nil ? "Controller: stick/D-pad walk · RT run · R-stick aim · A use/target · B cancel · X bag · Y character · LB tool · Mouse/keys still active" : player == nil ? "Drag / arrows: pan   T: statics   R: Britain   Command-L: login" : "Arrows: walk / combine for diagonals   Shift/Caps: run   Right-hold: move   Space: use   U: equipped tool   P: character   K: skills   J: journal   S: spells   M: map   B: backpack   H: recenter   Enter: chat   Command-L: connection",at:NSPoint(x:12,y:bounds.height-25))
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
                    useFacingObject()
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
                if !event.isARepeat { movementKeys.press(event.keyCode, direction: direction) }
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
        case (_, "t"):
            guard !event.isARepeat else { return }
            showStatics.toggle()
            lastRenderDiagnostic = -.infinity
            Telemetry.shared.record("preview_statics_toggled", ["enabled":showStatics])
        case (_, "r"): cx = 1435; cy = 1695
        default: super.keyDown(with: event); return
        }
        refresh()
    }

    private func useFacingObject() {
        guard let player else { return }
        do {
            if let item = try WorldInteraction.facingItem(player: player, items: groundObjects, assets: assets) {
                Telemetry.shared.record("space_use", ["serial": item.serial, "graphic": item.graphic])
                onUse?(item.serial)
            } else { Telemetry.shared.record("space_no_object") }
        } catch { Telemetry.shared.record("space_hit_error") }
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
    override func rightMouseDragged(with event: NSEvent) { if rightPoint != nil { rightPoint = convert(event.locationInWindow, from: nil) } }
    override func rightMouseUp(with event: NSEvent) { rightPoint = nil }

    override func mouseDown(with event: NSEvent) {
        discardMouseUp = false
        controllerPoint = nil
        window?.makeFirstResponder(self)
        dragged = false
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragCenter = (cx, cy)
        let point = convert(event.locationInWindow, from: nil), scale = worldScale
        groundDrag = !targeting && imageRect.contains(point) ? try? WorldHitTest.groundItem(assets: assets, animationTime:displayedAnimationTime, items: groundObjects, camera: displayedCamera, screenX: (point.x-imageRect.minX)/scale, screenY: (point.y-imageRect.minY)/scale, width:displayedWidth, height:displayedHeight) : nil
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
            let scale = worldScale
            groundPreview?.destination = NSRect(x: point.x-Double(sprite.width)*scale/2, y: point.y-Double(sprite.height)*scale/2, width: Double(sprite.width)*scale, height: Double(sprite.height)*scale)
            groundPreview?.needsDisplay = true
            return
        }
        guard player == nil || debugCamera else { return }
        let scale = worldScale
        let dx = (point.x - origin.x) / scale, dy = (point.y - origin.y) / scale
        let newX = dragCenter.0 - Int(((dx + dy) / 44).rounded())
        let newY = dragCenter.1 - Int(((dy - dx) / 44).rounded())
        if cx != newX || cy != newY { followPlayer = false; cx = newX; cy = newY; refresh() }
    }
    private func drawWalkRoute() {
        guard let player, !walkRoute.isEmpty else { return }
        let scale = worldScale
        func project(_ x:Double,_ y:Double,_ z:Double)->NSPoint {
            NSPoint(x:imageRect.minX+(worldCenterX+(x-y-displayedCamera.x+displayedCamera.y)*22)*scale,
                    y:imageRect.minY+(worldCenterY+(x+y-displayedCamera.x-displayedCamera.y)*22-z*4+22)*scale)
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
        let scale = worldScale
        if let selected = hovered, let item = groundObjects.first(where: { $0.serial == selected.serial }),
           let appearance = try? WorldItemAppearance.load(item,assets:assets,at:displayedAnimationTime) {
            let sprite = appearance.sprite
            let x = (worldCenterX + (Double(item.x-item.y)-displayedCamera.x+displayedCamera.y)*22).rounded() + Double(appearance.offsetX)
            let y = (worldCenterY + (Double(item.x+item.y)-displayedCamera.x-displayedCamera.y)*22-Double(item.z*4)).rounded()+Double(appearance.offsetY)
            NSGraphicsContext.saveGraphicsState(); imageRect.clip()
            NSColor.yellow.withAlphaComponent(0.85).setFill()
            func opaque(_ x: Int, _ y: Int) -> Bool {
                appearance.opaque(x:x,y:y)
            }
            for sy in 0..<sprite.height {
                for sx in 0..<sprite.width where opaque(sx,sy) && (!opaque(sx-1,sy) || !opaque(sx+1,sy) || !opaque(sx,sy-1) || !opaque(sx,sy+1)) {
                    NSRect(x: imageRect.minX+(x+Double(sx))*scale, y: imageRect.minY+(y+Double(sy))*scale, width: scale, height: scale).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
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
            let top = item.flatMap { try? WorldItemAppearance.load($0,assets:assets,at:displayedAnimationTime)?.offsetY } ?? (44-65)
            let x = imageRect.minX+(worldCenterX+(px-py-displayedCamera.x+displayedCamera.y)*22)*scale
            var y = imageRect.minY+(worldCenterY+(px+py-displayedCamera.x-displayedCamera.y)*22-pz*4+Double(top))*scale-4
            let textWidth = min(300,max(1,imageRect.width-8))
            for entry in overheadSpeech.entries.filter({ $0.serial == serial }).reversed() {
                let key=UInt32(entry.font)<<16 | UInt32(entry.hue)
                let bitmap:ClassicText
                if let cached=speechFonts[key] { bitmap=cached }
                else {
                    if speechFonts.count>=32 { speechFonts.removeAll() }
                    var rgb:(UInt8,UInt8,UInt8)=(255,255,255)
                    if let palette=try? assets.huePalette(Int(entry.hue)) { rgb=palette.color(red:255,green:255,blue:255) }
                    bitmap=ClassicText(assets.fonts,font:Int(entry.font),color:rgb); speechFonts[key]=bitmap
                }
                let lines=Array(bitmap.lines(entry.text,width:textWidth).prefix(6))
                let lineHeight=max(18,lines.map { bitmap.size($0).height+2 }.max() ?? 18)
                y -= CGFloat(lines.count)*lineHeight+2
                for (index,line) in lines.enumerated() {
                    let width=bitmap.size(line).width
                    let left=max(imageRect.minX+4,min(imageRect.maxX-width-4,x-width/2))
                    bitmap.draw(line,at:NSPoint(x:left,y:y+CGFloat(index)*lineHeight))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func groundDropLocation(windowPoint:NSPoint)->TargetSelection? {
        let point = convert(windowPoint,from:nil)
        guard let player, imageRect.contains(point), hitTest(superview?.convert(windowPoint,from:nil) ?? point) === self else { return nil }
        let scale = worldScale
        let visibility = (try? WorldVisibility.around(player:player,assets:assets)) ?? WorldVisibility()
        guard let location = try? WorldHitTest.location(assets:assets,animationTime:displayedAnimationTime,camera:displayedCamera,screenX:(point.x-imageRect.minX)/scale,screenY:(point.y-imageRect.minY)/scale,visibility:visibility, width:displayedWidth, height:displayedHeight),
              max(abs(location.x-player.x),abs(location.y-player.y)) <= 2 else { return nil }
        return location
    }
    override func mouseUp(with event: NSEvent) {
        if discardMouseUp { discardMouseUp = false; return }
        defer { dragOrigin = nil; groundDrag = nil; groundPreview?.removeFromSuperview(); groundPreview = nil }
        if dragged, let item = groundDrag { onGroundDrop?(item, event.locationInWindow); return }
        guard !dragged, player != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        clickWorld(at:point,clickCount:event.clickCount,shift:event.modifierFlags.contains(.shift))
    }
    private func clickWorld(at point:NSPoint,clickCount:Int,shift:Bool) {
        guard imageRect.contains(point) else { return }
        let scale = worldScale
        do {
            let screenX = (point.x - imageRect.minX) / scale, screenY = (point.y - imageRect.minY) / scale
            if targeting, let mobile = try WorldHitTest.mobile(assets: assets, mobiles: mobiles,
                presentations: motion.presentations(at: ProcessInfo.processInfo.systemUptime), camera: displayedCamera, screenX: screenX, screenY: screenY, equipment:equipment, width:displayedWidth, height:displayedHeight) {
                onTarget?(TargetSelection(serial: mobile.serial, x: mobile.x, y: mobile.y, z: mobile.z, graphic: mobile.body)); return
            }
            if let item = try WorldHitTest.groundItem(assets: assets, animationTime:displayedAnimationTime, items: groundObjects, camera: displayedCamera,
                screenX: (point.x - imageRect.minX) / scale, screenY: (point.y - imageRect.minY) / scale, width:displayedWidth, height:displayedHeight) {
                if targeting {
                    onTarget?(TargetSelection(serial: item.serial, x: item.x, y: item.y, z: item.z, graphic: item.graphic)); return
                }
                if clickCount == 1 && shift { onPickup?(item); return }
                if clickCount == 1 { onInspect?(item.serial) }
                let door = try assets.isDoor(graphic: item.graphic)
                Telemetry.shared.record("world_item_clicked", ["serial": item.serial, "graphic": item.graphic, "door": door, "clicks": clickCount])
                // Doors use one click; other world objects retain classic double-click use.
                if door && clickCount == 1 {
                    onWalkTo?(TargetSelection(x:item.x,y:item.y,z:item.z,graphic:item.graphic),item.serial,running)
                } else if !door && clickCount == 2 { onUse?(item.serial) }
            } else if targeting {
                let visibility = try player.map { try WorldVisibility.around(player: $0, assets: assets, additionalTiles: groundItems) } ?? WorldVisibility()
                if let location = try WorldHitTest.location(assets: assets, animationTime:displayedAnimationTime, camera: displayedCamera, screenX: screenX, screenY: screenY, visibility: visibility, width:displayedWidth, height:displayedHeight) { onTarget?(location) }
            } else if let mobile = try WorldHitTest.mobile(assets: assets, mobiles: mobiles, presentations: motion.presentations(at: ProcessInfo.processInfo.systemUptime), camera: displayedCamera, screenX: screenX, screenY: screenY, equipment:equipment, width:displayedWidth, height:displayedHeight) {
                if clickCount == 1 { onInspect?(mobile.serial) }
                if clickCount == 2, (player?.flags ?? 0) & 0x40 != 0 { onAttack?(mobile.serial) }
            } else if clickCount == 1 {
                let visibility = try player.map { try WorldVisibility.around(player:$0,assets:assets,additionalTiles:groundItems) } ?? WorldVisibility()
                if let location = try WorldHitTest.location(assets:assets,animationTime:displayedAnimationTime,camera:displayedCamera,screenX:screenX,screenY:screenY,visibility:visibility,additionalTiles:groundItems, width:displayedWidth, height:displayedHeight) {
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
    private var travelPanel:TravelPanel?
    private var deathPanel:DeathPanel?
    private var textPromptPanel:TextPromptPanel?
    private var tradePanel:TradePanel?
    private var huePickerPanel:HuePickerPanel?
    private var serverGumpPanels:[UInt64:ServerGumpPanel] = [:]
    private var serverMenuPanel:ServerMenuPanel?
    private var spellShortcuts:[UInt64:SpellShortcut] = [:]
    private let shortcutLayout=SpellShortcutLayout()
    private var spellbooks:[UInt32:SpellbookPanel] = [:]
    private func toggleMap() {
        guard let view = worldView, view.player != nil else { return }
        if let mapPanel, mapPanel.superview != nil { mapPanel.removeFromSuperview() }
        else {
            let panel = mapPanel ?? MapPanel(assets:assets); mapPanel = panel
            panel.onInspect = { [weak self] in self?.loginOverlay?.inspect(serial:$0,automatic:true) }
            panel.onTravel = { [weak self] x,y in
                self?.travelOnMap(x:x,y:y)
                self?.window?.makeFirstResponder(self?.worldView)
            }
            panel.groundItems = view.groundObjects; panel.combatTarget = view.combatTarget
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
        panel.onHelp = { [weak self] in self?.loginOverlay?.requestHelp() }
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
                    panel?.dismissObjectWindow(oldest.serial)
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
                bag.onClose = { [weak self,weak panel] in
                    panel?.dismissObjectWindow(container.serial)
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
            panel.onGraphicEffect = { [weak self] effect in
                self?.worldView?.effects.append(effect,at:ProcessInfo.processInfo.systemUptime)
                self?.worldView?.refresh()
            }
            panel.onAnimation = { [weak self] in self?.worldView?.playAnimation($0) }
            panel.onMobileDeath = { [weak self] in self?.worldView?.playDeath($0,mobile:$1,equipment:$2) }
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
                vendor.onBuy = { [weak panel] quantities in
                    guard let panel else { return "Vendor session closed. Request stock again." }
                    return panel.submitVendorTrade(quantities)
                }
                vendor.onClose = { [weak panel] in panel?.closeVendor() }
                view.addSubview(vendor); self.vendorPanel = vendor
            }
            panel.onVendorClosed = { [weak self] in self?.vendorPanel?.removeFromSuperview(); self?.vendorPanel = nil }
            panel.itemWeight = { [weak self] graphic in (try? self?.assets.itemWeight(graphic:graphic)) ?? 255 }
            panel.blockingTravelDoor = { [weak self] start,next in
                guard let self,let view=self.worldView,!((view.player?.isGhost) ?? false),
                      let direction=WalkPath.direction(from:start,to:next) else { return nil }
                let doors=self.loginOverlay?.routeItems.filter {
                    max(abs($0.x-start.x),abs($0.y-start.y))<=1 && abs($0.z-start.z)<=16 &&
                    (($0.x==next.x && $0.y==next.y) || (start.x != next.x && start.y != next.y &&
                      (($0.x==next.x && $0.y==start.y) || ($0.x==start.x && $0.y==next.y)))) &&
                    (try? self.assets.isDoor(graphic:$0.graphic)) == true &&
                    self.loginOverlay?.travelDoorAlreadyChanged($0) != true
                } ?? []
                guard !doors.isEmpty,
                      let map=try? NavigationMap(assets:self.assets,center:start,additional:view.groundItems,radius:3),
                      map.step(from:start,direction:direction) == nil,
                      map.step(from:start,direction:direction,ignoringDoors:true) != nil else { return nil }
                return doors.sorted { a,b in
                    let da=abs(a.x-next.x)+abs(a.y-next.y), db=abs(b.x-next.x)+abs(b.y-next.y)
                    return da == db ? a.serial<b.serial : da<db
                }.first
            }
            panel.pickupDetour = { [weak self] start,item in
                guard let self,let view=self.worldView,
                      let map=try? NavigationMap(assets:self.assets,center:start,additional:view.groundItems,radius:16) else { return nil }
                return WalkPath.find(from:start,x:item.x,y:item.y,adjacent:true,goalZ:item.z,limit:512) {
                    map.step(from:$0,direction:$1)
                }
            }
            panel.onAutoPickupMode = { [weak self] in self?.worldView?.sidebar?.updatePickupMode($0) }
            panel.onSkills = { [weak self] in self?.skillsPanel?.update($0) }
            panel.onCombatTarget = { [weak self] target in
                self?.worldView?.combatTarget = target.serial
                self?.worldView?.refresh()
                self?.mapPanel?.combatTarget = target.serial
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
                self?.mapPanel?.receiveName(message)
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
            panel.onObjectWindowsClosed = { [weak self] serials in
                for serial in serials {
                    self?.containerPanels.removeValue(forKey:serial)?.removeFromSuperview()
                    self?.spellbooks.removeValue(forKey:serial)?.removeFromSuperview()
                }
            }
            panel.onContainerItems = { [weak self] items in
                self?.containerPanels.values.forEach { $0.update(items) }
                self?.spellbooks.values.forEach { $0.update(items) }
            }
            panel.onActionsCancelled = { [weak self] in
                self?.worldView?.cancelInteraction()
                self?.characterPanel?.cancelInteraction()
                self?.containerPanels.values.forEach { $0.cancelInteraction() }
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
                display.onOpenContainer = { [weak panel] serial in panel?.use(serial:serial) }
                display.onInspect = { [weak panel] serial in panel?.inspect(serial:serial) }
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
                book.onClose = { [weak self,weak panel] in
                    panel?.dismissObjectWindow(serial)
                    self?.spellbooks.removeValue(forKey:serial)
                }
                book.update(items)
                book.onCast = { [weak self, weak panel] id in
                    panel?.castSpell(id,book:serial)
                    self?.window?.makeFirstResponder(self?.worldView)
                }
                let scope=panel?.assistantScope ?? ""
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
                        shortcut.onClose = { [weak self] in
                            self?.spellShortcuts.removeValue(forKey:key)
                            self?.shortcutLayout.remove(book:serial,spell:id,scope:scope)
                        }
                        shortcut.onMoved = { [weak self,weak shortcut,weak view] in
                            guard let self,let shortcut,let view,view.bounds.width>0,view.bounds.height>0 else { return }
                            self.shortcutLayout.save(.init(book:serial,spell:id,x:Double(shortcut.frame.midX/view.bounds.width),y:Double(shortcut.frame.midY/view.bounds.height)),scope:scope)
                        }
                        self.spellShortcuts[key] = shortcut
                        Telemetry.shared.record("spell_shortcut_created",["id":id,"book":serial])
                    }
                    shortcut.removeFromSuperview(); view.addSubview(shortcut)
                    shortcut.place(at:view.convert(point,from:nil),in:view)
                    shortcut.onMoved?()
                }
                let known=ClassicSpells.contents(book:serial,items:items)
                for entry in self.shortcutLayout.entries(scope:scope) where entry.book == serial && known.contains(entry.spell) {
                    let key=UInt64(serial)<<32 | UInt64(entry.spell)
                    guard self.spellShortcuts[key] == nil else { continue }
                    let point=NSPoint(x:CGFloat(entry.x)*view.bounds.width,y:CGFloat(entry.y)*view.bounds.height)
                    book.onShortcut?(entry.spell,view.convert(point,to:nil))
                }
                book.removeFromSuperview(); view.addSubview(book)
            }
            panel.onGroundObjects = { [weak self] items in
                guard let view = self?.worldView else { return }
                view.groundObjects = items
                self?.mapPanel?.groundItems = items
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
            worldView?.onHoverInspect = { [weak panel] in panel?.inspect(serial:$0,automatic:true) }
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
                if player == nil || self?.mapPanel?.superview != nil { self?.mapPanel?.update(player:player,mobiles:view.mobiles) }
                if modeChanged { self?.characterPanel?.update(player:player,equipment:view.equipment) }
                view.sidebar?.updateMode(war:(player?.flags ?? 0) & 0x40 != 0, hidden:(player?.flags ?? 0) & 0x80 != 0)
                view.window?.invalidateCursorRects(for:view)
                view.sidebar?.isHidden = player == nil
                view.sidebar?.updateEquipment(view.equipment, player:player?.serial, assets:view.assets)
                if player == nil { self?.travelPanel?.removeFromSuperview(); self?.travelPanel=nil; self?.mapPanel?.onPickLocation=nil; view.resetDeathAnimations(); view.effects = WorldEffects(); self?.audio.stop(); view.sidebar?.updateStatus(nil); self?.skillsPanel?.update(SkillState()) }
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
            panel.onDoorOpenedRoute = { [weak self] destination,remaining,running in
                self?.approach(destination,action:nil,running:running,doorsRemaining:remaining)
            }
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
    private func showTravel() {
        guard let view=worldView,let login=loginOverlay,view.player != nil else { return }
        travelPanel?.removeFromSuperview()
        let panel=TravelPanel(assets:assets,scope:login.assistantScope); travelPanel=panel
        panel.onGo = { [weak self,weak panel] x,y in
            self?.travelOnMap(x:x,y:y,dropGathered:panel?.dropGatheredWhenOverloaded ?? false,bankGathered:panel?.bankGatheredOnArrival ?? false); self?.window?.makeFirstResponder(self?.worldView)
        }
        panel.onStop = { [weak self] in self?.loginOverlay?.cancelRoute() }
        panel.onPick = { [weak self,weak panel] in
            guard let self else { return }
            if self.mapPanel?.superview == nil { self.toggleMap() }
            self.mapPanel?.showWorld(); panel?.isHidden=true
            self.mapPanel?.onPickCancelled = { [weak panel] in panel?.isHidden=false }
            self.mapPanel?.onPickLocation = { [weak panel] x,y in panel?.picked(x:x,y:y); panel?.isHidden=false }
            self.chatPanel.append("Click the world map to choose a travel destination.")
        }
        view.addSubview(panel)
    }
    private var travelPlanning:Task<Void,Never>?
    private var travelWorker:Task<[WalkPoint]?,Never>?
    private func travelOnMap(x:Int,y:Int,dropGathered:Bool=false,bankGathered:Bool=false) {
        guard let view = worldView, let player = view.player, let panel = loginOverlay else { return }
        panel.cancelRoute()
        travelPlanning?.cancel(); travelWorker?.cancel()
        let start=WalkPoint(x:player.x,y:player.y,z:player.z)
        let directory=URL(fileURLWithPath:options.client),ghost=player.isGhost
        chatPanel.append("Planning the complete route, including bridges...")
        let worker=Task.detached(priority:.userInitiated) { ()->[WalkPoint]? in
            do {
                let assets=try ClientAssets(directory:directory)
                return try WorldTravelPlanner(assets:assets,ghost:ghost).find(from:start,x:x,y:y,adjacent:bankGathered,cancelled:{ Task.isCancelled })
            } catch { return nil }
        }
        travelWorker=worker
        panel.onRouteCancelled = { [weak self] in self?.travelPlanning?.cancel(); self?.travelWorker?.cancel() }
        travelPlanning=Task { [weak self,weak panel] in
            let route=await worker.value
            guard !Task.isCancelled,let self,let panel,let view=self.worldView,let current=view.player else { return }
            guard current.serial == player.serial,current.x == start.x,current.y == start.y,current.z == start.z else {
                self.chatPanel.append("Travel planning cancelled because your position changed. Choose Go again."); return
            }
            guard let route else { self.chatPanel.append("No complete walking route found within the search budget. Try a nearer waypoint."); return }
            // The reachable bank approach may be beside a wall/sign landmark.
            // Local replanning must follow that actual endpoint, not repeatedly
            // attempt the blocked landmark after the global route finishes.
            let endpoint=bankGathered ? (route.last ?? start) : WalkPoint(x:x,y:y,z:start.z)
            guard self.beginWorldTravel(route,start:start,x:endpoint.x,y:endpoint.y,panel:panel,view:view) else { return }
            panel.dropGatheredDuringTravel=dropGathered
            panel.bankGatheredOnArrival=bankGathered
        }
    }
    private func beginWorldTravel(_ itinerary:[WalkPoint],start:WalkPoint,x:Int,y:Int,panel:LoginOverlay,view:WorldView)->Bool {
        var progress=0
        let planner: (WalkPoint,Set<WalkPoint>)->[WalkPoint]? = { [weak self] start,blocked in
            guard let self,let view=self.worldView else { return nil }
            if start.x == x && start.y == y { return [] }
            if let reached=itinerary.indices.dropFirst(progress).prefix(96).first(where:{ itinerary[$0].x == start.x && itinerary[$0].y == start.y && abs(itinerary[$0].z-start.z)<=16 }) { progress=reached+1 }
            let candidates=itinerary.dropFirst(progress).prefix(64).filter { max(abs($0.x-start.x),abs($0.y-start.y))<=28 }
            guard let map=try? NavigationMap(assets:self.assets,center:start,additional:view.groundItems,radius:48,ghost:view.player?.isGhost == true) else { return nil }
            let enemies=view.mobiles.filter { $0.serial != view.player?.serial && ($0.isEnemy || $0.serial == view.combatTarget) }
            let openedLeaves=Set((self.loginOverlay?.travelDoorObstacles ?? []).filter { map.standingPoint(x:$0.x,y:$0.y,fromZ:$0.z) == nil })
            func route(to goal:WalkPoint,ignoringDoors:Bool)->[WalkPoint]? {
                TravelSafety.route(from:start,to:goal,enemies:enemies,cost:map.travelCost) { point,direction in
                    guard let next=map.step(from:point,direction:direction,ignoringDoors:ignoringDoors),!blocked.contains(next),
                          TravelSafety.clearsDoorLeaves(from:point,to:next,leaves:openedLeaves) else { return nil }
                    return next
                }
            }
            // A dynamic object may occupy the preferred section endpoint. Try
            // earlier forward waypoints instead of treating that one cell as the
            // only possible entry into the globally planned itinerary.
            let forward=candidates.filter { $0 != start }
            let goals=forward.reversed().enumerated().filter { $0.offset % 8 == 0 }.prefix(8).map(\.element)
            for goal in goals {
                if let path=route(to:goal,ignoringDoors:false) ?? route(to:goal,ignoringDoors:true),!path.isEmpty { return path }
            }
            Telemetry.shared.record("travel_section_blocked",["x":start.x,"y":start.y,"candidates":goals.count,"opened_doors":openedLeaves.count])
            return nil
        }
        guard let route=planner(start,[]) else { chatPanel.append("The route is planned, but a nearby obstacle blocks the first section."); return false }
        view.followPlayer=true
        panel.followRoute(route,action:nil,running:view.running,continuing:true,resolver:planner)
        chatPanel.append("Route planned: \(itinerary.count) steps. Starting travel.")
        Telemetry.shared.record("map_travel_requested",["x":x,"y":y,"steps":itinerary.count])
        return true
    }
    /// Door-free planning is only used to find the first gate. Actual walking
    /// always uses the ordinary collision map, then waits for a server update.
    private func routeThroughDoor(to destination:TargetSelection,start:WalkPoint,running:Bool,remaining:Int,map:NavigationMap)throws->Bool {
        guard let panel = loginOverlay,let view = worldView else { return false }
        let doors = try panel.routeItems.filter { item in
            guard max(abs(item.x-start.x),abs(item.y-start.y)) <= 24 else { return false }
            return try assets.isDoor(graphic:item.graphic)
        }.sorted { $0.serial < $1.serial }
        guard !doors.isEmpty else { return false }
        let doorCells = Set(doors.map { WalkPoint(x:$0.x,y:$0.y,z:$0.z) })
        guard let route = WalkPath.find(from:start,x:destination.x,y:destination.y,step:{ point,direction in
            // Do not cut diagonally past a door that has been relaxed only for
            // planning. Force a route through its cell so it can be identified.
            let delta = WalkPath.directions[Int(direction)]
            if delta.0 != 0 && delta.1 != 0 && doorCells.contains(where:{
                abs($0.z-point.z)<=16 && (($0.x == point.x+delta.0 && $0.y == point.y) || ($0.x == point.x && $0.y == point.y+delta.1))
            }) { return nil }
            return map.step(from:point,direction:direction,ignoringDoors:true)
        }) else { return false }
        for point in route {
            guard let door = doors.first(where:{ $0.x == point.x && $0.y == point.y && abs($0.z-point.z)<=16 }),
                  let approach = WalkPath.find(from:start,x:door.x,y:door.y,adjacent:true,goalZ:door.z,
                                                step:{ map.step(from:$0,direction:$1) }) else { continue }
            view.followPlayer = true
            panel.followRoute(approach,action:.openDoor(door,destination,remaining-1),running:running) { [weak self] position,blocked in
                guard let self,let view = self.worldView,
                      let current = try? NavigationMap(assets:self.assets,center:position,additional:view.groundItems,ghost:view.player?.isGhost == true) else { return nil }
                return WalkPath.find(from:position,x:door.x,y:door.y,adjacent:true,goalZ:door.z) { point,direction in
                    guard let next = current.step(from:point,direction:direction),!blocked.contains(next) else { return nil }
                    return next
                }
            }
            Telemetry.shared.record("door_route_planned",["serial":door.serial,"steps":approach.count,"remaining":remaining-1])
            return true
        }
        return false
    }
    private func approach(_ location:TargetSelection, action:LoginOverlay.ArrivalAction?, running:Bool, doorsRemaining:Int = 4) {
        guard let view = worldView, let player = view.player, let panel = loginOverlay else { return }
        panel.cancelRoute()
        let start = WalkPoint(x:player.x,y:player.y,z:player.z)
        guard max(abs(start.x-location.x),abs(start.y-location.y)) <= 24 else {
            chatPanel.append("Choose a closer destination."); return
        }
        do {
            let map = try NavigationMap(assets:assets,center:start,additional:view.groundItems,ghost:view.player?.isGhost == true)
            var location = location
            if action == nil, location.graphic != 0,
               try assets.itemFlags(graphic:location.graphic) & 0x10000000 != 0 {
                let tiles = try assets.region(x:location.x,y:location.y,radius:2) + view.groundItems
                let roofs = try tiles.filter { tile in
                    guard tile.isStatic else { return false }
                    return try assets.itemFlags(graphic:tile.art-0x4000) & 0x10000000 != 0
                }.map { WalkPoint(x:$0.x,y:$0.y,z:$0.z) }
                let roof = WalkPoint(x:location.x,y:location.y,z:location.z)
                guard let floor = WalkDestination.beneathRoof(roof,footprint:roofs,player:start,standing:{
                    map.standingPoint(x:$0,y:$1,fromZ:start.z)
                }) else { chatPanel.append("No reachable floor beneath that roof."); return }
                location = TargetSelection(x:floor.x,y:floor.y,z:floor.z,graphic:0)
                Telemetry.shared.record("roof_walk_floor",["roof_x":roof.x,"roof_y":roof.y,"roof_z":roof.z,"x":floor.x,"y":floor.y,"z":floor.z])
            }
            // A mineable cliff face is not a floor to stand on. Reach a neighboring
            // walkable tile without requiring the clicked cliff's elevation.
            let goalZ:Int?
            if case .toolTarget = action { goalZ = nil } else { goalZ = action == nil ? nil : location.z }
            guard let route = WalkPath.find(from:start,x:location.x,y:location.y,adjacent:action != nil,
                                            goalZ:goalZ,
                                            step:{ map.step(from:$0,direction:$1) }) else {
                if action == nil, !player.isGhost, doorsRemaining > 0,
                   try routeThroughDoor(to:location,start:start,running:running,remaining:doorsRemaining,map:map) { return }
                chatPanel.append("No clear route to that location.")
                Telemetry.shared.record("walk_route_unreachable",["x":location.x,"y":location.y]); return
            }
            view.followPlayer = true
            panel.followRoute(route,action:action,running:running) { [weak self] start,blocked in
                guard let self, let view = self.worldView,
                      let map = try? NavigationMap(assets:self.assets,center:start,additional:view.groundItems,ghost:view.player?.isGhost == true) else { return nil }
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
        ClassicControlArt.install(assets)
        ClassicNativeFont.install(assets.fonts)
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
        let sidebar = PlaySidebar(definitions: assets.skills,assets:assets)
        sidebar.isHidden = true; view.sidebar = sidebar; skillsPanel = sidebar.skills
        sidebar.onPickupMode = { [weak self] in self?.loginOverlay?.setAutoPickup($0) }
        sidebar.skills.onUse = { [weak self] in self?.loginOverlay?.useSkill($0) }
        sidebar.onCommand = { [weak self] command in
            switch command {
            case 0: self?.showCharacter()
            case 1: self?.loginOverlay?.openBackpack()
            case 2: self?.loginOverlay?.useEquippedTool()
            case 4: self?.showTravel()
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
