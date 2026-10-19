import AppKit
import UOCore

@MainActor
final class LoginOverlay: NSViewController, NSTextFieldDelegate {
    private let connection:GameConnection
    private var savedLogin:SavedLogin
    private let loginDefaults:UserDefaults
    private let localLoginButton:ClassicButton
    private let primaryLoginButton:ClassicButton
    private let characterSelection: CharacterSelectionPanel
    private let characterCreation: CharacterCreationPanel
    private let card:NSView = FlippedLoginControls()
    private let artwork:LoginArtwork
    private let settings:ClassicPanel
    private let introControls:NSView = FlippedLoginControls()
    private(set) var characterDisplayName = ""
    private var creationSlot: UInt32 = 0
    private var pendingDeletion: UInt32?
    private let host = ClassicEntry(string: "login.uo1998.com")
    private let port = ClassicEntry(string: "5000")
    private let account = ClassicEntry(string: "")
    private let password = ClassicSecureEntry(string: "")
    private let rememberPassword = NSButton(checkboxWithTitle: "Remember password in macOS Keychain", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Connect using the 1.25.32 protocol.")
    private let choices:ClassicChoice
    private let cityChoice:ClassicChoice
    private var cities: [StartingCity] = []
    private let characterName = ClassicEntry(string: "Avatar")
    private let female = NSButton(checkboxWithTitle: "Female character", target: nil, action: nil)
    private var secondaryButtons: [NSButton] = []
    private let action: ClassicButton
    private var servers: [LoginServer] = []
    private var characters: [GameCharacter] = []
    private var framer = GamePacketFramer()
    private var world = WorldState()
    private var openObjectWindows=OpenObjectWindows()
    var onObjectWindowsClosed:((Set<UInt32>)->Void)?
    func dismissObjectWindow(_ serial:UInt32) { openObjectWindows.dismiss(serial) }
    private var playerSerial: UInt32?
    private var loginComplete = false
    private(set) var characterStatus: CharacterStatus?
    private var statusRefreshTask: Task<Void, Never>?
    private var combatTarget = CombatTarget()
    var onCombatTarget: ((CombatTarget) -> Void)?
    var onCharacterStatus: ((CharacterStatus?) -> Void)?
    func toggleWarMode() {
        guard loginComplete, let serial = playerSerial, let player = world.mobiles[serial] else { return }
        let enabled = player.flags & 0x40 == 0
        connection.send(CombatPackets.mode(enabled))
        Telemetry.shared.record("war_mode_requested",["enabled":enabled])
    }
    func attack(serial:UInt32) {
        guard loginComplete, let playerSerial, serial != playerSerial,
              (world.mobiles[playerSerial]?.flags ?? 0) & 0x40 != 0,
              world.mobiles[serial] != nil, let packet = try? CombatPackets.attack(serial) else { return }
        connection.send(packet)
        Telemetry.shared.record("attack_requested",["serial":serial])
    }
    func requestHelp() {
        guard loginComplete else { return }
        cancelRoute()
        connection.send(HelpPackets.request)
        Telemetry.shared.record("help_requested")
        onInventoryMessage?("Requesting the server help menu…")
    }
    func requestStatus() {
        guard loginComplete, let playerSerial else { return }
        connection.send(CharacterStatus.request(serial: playerSerial))
        Telemetry.shared.record("status_requested")
    }
    private func scheduleStatusRefresh() {
        guard statusRefreshTask == nil else { return }
        statusRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.statusRefreshTask = nil
            self.requestStatus()
        }
    }
    private(set) var skills = SkillState()
    var onSkills: ((SkillState) -> Void)?
    func requestSkills() {
        guard loginComplete, let playerSerial else { return }
        connection.send(SkillState.request(serial: playerSerial))
        Telemetry.shared.record("skills_requested")
    }
    func useSkill(_ id: Int) {
        guard loginComplete, let packet = try? SkillState.use(id: id) else { return }
        equippedTargetTool = nil
        if case .toolTarget = routeAction { cancelRoute() }
        connection.send(packet)
        Telemetry.shared.record("skill_used", ["id": id])
    }
    private var movement = PlayerMovement()
    private var reportedMovementSyncTimeout=false
    var onEquipment: (([EquippedItem]) -> Void)?
    var onPlayer: ((WorldMobile?) -> Void)?
    var predictedElevation: ((Int, Int, Int) -> Int)?
    var onWalkRoute: (([WalkPoint])->Void)?
    private var walkRoute:[WalkPoint]?
    enum ArrivalAction {
        case use(UInt32), pickup(UInt32, Int), attack(UInt32)
        case toolTarget(TargetRequest,TargetSelection,UInt32)
        case openDoor(GroundItem,TargetSelection,Int)
        var serial: UInt32 {
            switch self { case .use(let s), .pickup(let s,_), .attack(let s): return s; case .openDoor(let door,_,_): return door.serial; case .toolTarget(_,let target,_): return target.serial }
        }
    }
    private var routeAction: ArrivalAction?
    var routeItems: [GroundItem] { Array(world.items.values) }
    var onDoorOpenedRoute: ((TargetSelection,Int,Bool)->Void)?
    private var waitingDoor: (item:GroundItem,destination:TargetSelection,remaining:Int,running:Bool,wait:DoorOpeningWait)?
    var assistantScope:String { "\(host.stringValue):\(port.stringValue):\(playerSerial ?? 0)" }
    var blockingTravelDoor:((WalkPoint,WalkPoint)->GroundItem?)?
    var pickupDetour:((WalkPoint,GroundItem)->[WalkPoint]?)?
    private var travelDoor:(item:GroundItem,wait:DoorOpeningWait)?
    private var openedTravelDoors:[UInt32:GroundItem]=[:]
    func travelDoorAlreadyChanged(_ item:GroundItem)->Bool {
        guard let opened=openedTravelDoors[item.serial] else { return false }
        return !DoorOpeningWait.geometryChanged(from:opened,to:item)
    }
    var travelDoorObstacles:Set<WalkPoint> {
        Set(openedTravelDoors.values.compactMap { opened in
            guard let current=world.items[opened.serial],travelDoorAlreadyChanged(current) else { return nil }
            return WalkPoint(x:current.x,y:current.y,z:current.z)
        })
    }
    private var detourItem:UInt32?
    private var detourArrivedAt:TimeInterval?
    private var detourAttempts:Set<UInt32>=[]
    private var nextDetourAt:TimeInterval=0
    private var routeRunning = false
    private var routeResolver: ((WalkPoint,Set<WalkPoint>)->[WalkPoint]?)?
    private var routeRecovery=RouteRecovery()
    private var needsRouteRetry = false
    private var routeContinues = false
    private var routeSegments = 0
    private var travelActivity:NSObjectProtocol?
    var onRouteCancelled:(()->Void)?
    private func invalidateInteractionObjects(_ removed:Set<UInt32>) {
        guard !removed.isEmpty else { return }
        for serial in removed { openedTravelDoors.removeValue(forKey:serial) }
        var affected=false
        if let action=routeAction {
            affected=action.serial != 0 && removed.contains(action.serial)
            if case .toolTarget(_,_,let tool)=action { affected = affected || removed.contains(tool) }
        }
        if let waitingDoor { affected = affected || removed.contains(waitingDoor.item.serial) }
        if affected {
            cancelRoute()
            onInventoryMessage?("The target or tool is no longer nearby; route stopped.")
            Telemetry.shared.record("arrival_route_invalidated",["reason":"object_removed"])
        }
        if let tool=equippedTargetTool,removed.contains(tool) {
            target(nil); equippedTargetTool=nil
        }
    }
    func cancelRoute() {
        dropGatheredDuringTravel=false; bankGatheredOnArrival=false; bankingRequested=false
        bankingCancelled=true
        onRouteCancelled?()
        if let activity=travelActivity { ProcessInfo.processInfo.endActivity(activity); travelActivity=nil }
        waitingDoor = nil; travelDoor=nil; detourItem=nil; detourArrivedAt=nil; detourAttempts=[]; nextDetourAt=0
        if walkRoute != nil { Telemetry.shared.record("walk_route_cancelled") }
        walkRoute = nil; routeAction = nil; onWalkRoute?([])
        routeResolver = nil; routeRecovery=RouteRecovery(); needsRouteRetry = false; routeContinues = false; routeSegments = 0
    }
    func followRoute(_ route:[WalkPoint], action:ArrivalAction?, running:Bool, continuing:Bool = false, resolver: @escaping (WalkPoint,Set<WalkPoint>)->[WalkPoint]?) {
        guard loginComplete else { return }
        if travelActivity == nil {
            travelActivity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Completing requested Ultima Online travel")
        }
        routeRecovery=RouteRecovery(); needsRouteRetry=false
        travelDoor=nil; detourItem=nil; detourArrivedAt=nil; detourAttempts=[]; nextDetourAt=0
        routeResolver = resolver; routeContinues = continuing
        walkRoute = route; routeAction = action; routeRunning = running; onWalkRoute?(route)
        Telemetry.shared.record("walk_route_started",["steps":route.count,"target":action?.serial as Any? ?? NSNull(),"running":running])
    }
    var itemWeight:((Int)->Int)?
    private var autoPickup = AutoPickup()
    var dropGatheredDuringTravel=false
    var bankGatheredOnArrival=false
    private var bankingRequested=false
    private var banking:GatheredBanking?
    private var bankingCancelled=false
    private var bankContentsContext:UInt32?
    private var bankTransferUntil:TimeInterval=0
    private var gatheredDrop:GatheredDrop?
    private var awaitingDropWeight:TimeInterval?
    private var inventoryRecoveryBusy:Bool { gatheredDrop != nil || awaitingDropWeight != nil || banking != nil || bankingRequested || ProcessInfo.processInfo.systemUptime<bankTransferUntil }
    private var manualInventoryAt:TimeInterval = -.infinity
    var onAutoPickupMode:((Int)->Void)?
    func setAutoPickup(_ value:Int) {
        autoPickup.mode=AutoPickup.Mode(rawValue:value) ?? .off
        onAutoPickupMode?(autoPickup.mode.rawValue)
        Telemetry.shared.record("auto_pickup_mode",["mode":autoPickup.mode.rawValue])
    }
    private func tickAutoPickup(allowed:Bool) {
        let now=ProcessInfo.processInfo.systemUptime
        let wasPending=autoPickup.pending != nil
        autoPickup.update(contents:Array(world.containerItems.values),at:now)
        if wasPending && autoPickup.pending == nil && autoPickup.mode != .off {
            Telemetry.shared.record("auto_pickup_confirmed",[
                "tracked_stacks":autoPickup.gathered.credits.count,
                "tracked_amount":autoPickup.gathered.credits.values.reduce(0) { $0+$1.amount }
            ])
        }
        if wasPending && autoPickup.pending == nil && autoPickup.mode == .off {
            onInventoryMessage?(autoPickup.stoppedReason ?? "Auto-pickup stopped."); onAutoPickupMode?(0)
        }
        guard travelDoor == nil,waitingDoor == nil,!inventoryRecoveryBusy,(detourItem == nil || movement.pendingCount == 0),allowed,loginComplete,trade == nil,combatTarget.serial == nil,targetRequest == nil,now-manualInventoryAt>2,
              let serial=playerSerial,let player=world.mobiles[serial],
              let weight=characterStatus?.weight,let strength=characterStatus?.strength,
              weight < 40+strength*7/2-10,
              let bag=world.equipment.values.first(where:{$0.owner==serial && $0.layer==21}),
              let item=autoPickup.select(items:Array(world.items.values),player:player,at:now,portable:{ (self.itemWeight?($0.graphic) ?? 255)<255 }) else { return }
        guard TravelSafety.pickupIsSafe(from:WalkPoint(x:player.x,y:player.y,z:player.z),
              target:WalkPoint(x:item.x,y:item.y,z:item.z),path:[],
              enemies:world.mobiles.values.filter { $0.serial != serial && $0.isEnemy }) else { return }
        guard let unitWeight=itemWeight?(item.graphic),unitWeight<255,
              weight+unitWeight*max(1,item.amount)<40+strength*7/2-10 else {
            autoPickup.skip(item.serial)
            onInventoryMessage?("Auto-pickup skipped a stack that may exceed carrying capacity.")
            Telemetry.shared.record("auto_pickup_result",["outcome":"skipped_weight"]); return
        }
        do {
            let packets=try world.movePackets(serial:item.serial,amount:max(1,item.amount),player:serial,x:0xFFFF,y:0xFFFF,target:bag.serial,z:0)
            autoPickup.begin(item,bag:bag.serial,contents:Array(world.containerItems.values),at:now)
            packets.forEach { connection.send($0) }
            Telemetry.shared.record("auto_pickup_started",["serial":item.serial,"graphic":item.graphic,"amount":item.amount])
        } catch { autoPickup.stop("Auto-pickup stopped: item cannot be moved."); onAutoPickupMode?(0) }
    }
    /// Called even with the window hidden, like the travel movement timer.
    private func tickGatheredBanking()->Bool {
        guard loginComplete,let serial=playerSerial,let player=world.mobiles[serial] else { return false }
        if bankingRequested {
            guard autoPickup.pending==nil,movement.pendingCount==0,!movement.awaitingPosition else { return true }
            bankingRequested=false
            guard !player.isGhost,trade==nil,targetRequest==nil,combatTarget.serial==nil else {
                cancelRoute(); onInventoryMessage?("Banking stopped for your current interaction."); return false
            }
            var runner=GatheredBanking()
            _=runner.begin(player:serial,at:WalkPoint(x:player.x,y:player.y,z:player.z),time:ProcessInfo.processInfo.systemUptime)
            banking=runner; bankingCancelled=false; bankContentsContext=nil
            _=say("bank")
            onInventoryMessage?("Requesting your bank box…")
            Telemetry.shared.record("gathered_bank_open_requested")
        }
        guard var runner=banking else { return false }
        if trade != nil || targetRequest != nil || combatTarget.serial != nil || player.isGhost { bankingCancelled=true }
        if bankingCancelled && runner.state != .transferring { runner.stop("Banking cancelled.") }
        guard let bag=world.equipment.values.first(where:{$0.owner==serial && $0.layer==21}) else {
            banking=nil; cancelRoute(); onInventoryMessage?("Banking stopped: backpack unavailable."); return false
        }
        let command=runner.next(position:WalkPoint(x:player.x,y:player.y,z:player.z),backpack:bag.serial,
                                equipment:Array(world.equipment.values),contents:Array(world.containerItems.values),
                                gathered:autoPickup.gathered,time:ProcessInfo.processInfo.systemUptime)
        banking=runner
        switch runner.state {
        case .complete:
            banking=nil; bankTransferUntil=0
            if let activity=travelActivity { ProcessInfo.processInfo.endActivity(activity); travelActivity=nil }
            onInventoryMessage?("Gathered goods banked. Existing belongings were kept.")
            Telemetry.shared.record("gathered_banking_completed"); return false
        case .stopped(let reason):
            banking=nil
            if let activity=travelActivity { ProcessInfo.processInfo.endActivity(activity); travelActivity=nil }
            onInventoryMessage?(reason)
            Telemetry.shared.record("gathered_banking_stopped"); return false
        default: break
        }
        if case .deposit(let item,let amount,let bank)=command {
            do {
                let packets=try world.movePackets(serial:item,amount:amount,player:serial,x:0xFFFF,y:0xFFFF,target:bank,z:0)
                bankTransferUntil=ProcessInfo.processInfo.systemUptime+5
                packets.forEach { connection.send($0) }
                onInventoryMessage?("Banking gathered goods…")
                Telemetry.shared.record("gathered_bank_deposit",["serial":item,"amount":amount,"bank":bank])
            } catch { banking?.stop("Gathered item is no longer available.") }
        }
        return true
    }
    /// Returns true while movement must wait for an outstanding transfer.
    private func tickGatheredRecovery()->Bool {
        let now=ProcessInfo.processInfo.systemUptime
        if let drop=gatheredDrop {
            switch drop.result(contents:Array(world.containerItems.values),ground:Array(world.items.values),at:now) {
            case .waiting: return true
            case .confirmed:
                for item in drop.droppedItems(Array(world.items.values)) { autoPickup.skip(item.serial) }
                gatheredDrop=nil; awaitingDropWeight=now
                requestStatus()
                onInventoryMessage?("Gathered goods dropped. Waiting for updated carrying weight…")
                Telemetry.shared.record("gathered_drop_confirmed",["serial":drop.serial,"amount":drop.amount])
                return true
            case .refused,.timedOut:
                gatheredDrop=nil; cancelRoute()
                autoPickup.stop("Travel stopped: gathered-item drop was not confirmed. Check your backpack and the ground.")
                onAutoPickupMode?(0); onInventoryMessage?(autoPickup.stoppedReason!)
                Telemetry.shared.record("gathered_drop_stopped",["serial":drop.serial])
                return true
            }
        }
        if let since=awaitingDropWeight {
            if now-since>=5 {
                awaitingDropWeight=nil; cancelRoute()
                autoPickup.stop("No updated carrying weight."); onAutoPickupMode?(0)
                onInventoryMessage?("Travel stopped: no updated carrying weight after dropping goods.")
            }
            return true
        }
        guard dropGatheredDuringTravel,walkRoute != nil,loginComplete,
              let serial=playerSerial,let player=world.mobiles[serial],!player.isGhost,
              let weight=characterStatus?.weight,let strength=characterStatus?.strength,
              weight>40+strength*7/2 else { return false }
        // Finish any predicted steps and outstanding pickup before changing inventory.
        guard movement.pendingCount==0,!movement.awaitingPosition else { return true }
        guard autoPickup.pending==nil,now-manualInventoryAt>2 else { return true }
        guard trade==nil,targetRequest==nil,combatTarget.serial==nil else {
            cancelRoute(); onInventoryMessage?("Overload recovery stopped for your active interaction."); return true
        }
        guard let bag=world.equipment.values.first(where:{$0.owner==serial && $0.layer==21}),
              let credit=autoPickup.gathered.transferable(in:bag.serial,includeGold:false).first(where:{
                  let w=itemWeight?($0.graphic) ?? 255; return w>0 && w<255
              }),let unit=itemWeight?(credit.graphic) else {
            cancelRoute(); onInventoryMessage?("Overloaded: no confirmed gathered goods can be dropped. Your gold and existing items were kept.")
            return true
        }
        let excess=weight-(40+strength*7/2)+1
        let amount=min(credit.amount,(excess+unit-1)/unit)
        let point=WalkPoint(x:player.x,y:player.y,z:player.z)
        do {
            let packets=try world.movePackets(serial:credit.serial,amount:amount,player:serial,x:point.x,y:point.y,target:0xFFFFFFFF,z:point.z)
            gatheredDrop=GatheredDrop(credit:credit,amount:amount,point:point,contents:Array(world.containerItems.values),ground:Array(world.items.values),at:now)
            packets.forEach { connection.send($0) }
            onInventoryMessage?("Dropping newly gathered goods to recover carrying capacity…")
            Telemetry.shared.record("gathered_drop_started",["serial":credit.serial,"amount":amount,"x":point.x,"y":point.y])
        } catch { cancelRoute(); onInventoryMessage?("Travel stopped: gathered item is no longer available.") }
        return true
    }
    func tickMovement(allowRoute:Bool = true) {
        if loginComplete, let packet = movement.poll(at: ProcessInfo.processInfo.systemUptime) {
            Telemetry.shared.record("movement_position_sync", ["pending": movement.pendingCount])
            connection.send(packet)
        }
        if movement.positionSyncTimedOut && !reportedMovementSyncTimeout {
            reportedMovementSyncTimeout=true
            cancelRoute()
            onInventoryMessage?("Waiting for the server to confirm your position. If this persists, reconnect.")
            Telemetry.shared.record("movement_position_sync_timeout")
        } else if !movement.positionSyncTimedOut { reportedMovementSyncTimeout=false }
        tickAutoPickup(allowed:allowRoute || walkRoute != nil)
        if tickGatheredRecovery() { return }
        if tickGatheredBanking() { return }
        if var waiting=travelDoor {
            switch waiting.wait.result(door:world.items[waiting.item.serial],at:ProcessInfo.processInfo.systemUptime) {
            case .waiting: return
            case .retry:
                guard let current=world.items[waiting.item.serial],let serial=playerSerial,let player=world.mobiles[serial],
                      max(abs(current.x-player.x),abs(current.y-player.y))<=1,abs(current.z-player.z)<=16 else {
                    cancelRoute(); return
                }
                waiting.wait.didRetry(at:ProcessInfo.processInfo.systemUptime); travelDoor=waiting
                connection.send(InteractionPackets.use(serial:current.serial))
                Telemetry.shared.record("travel_door_retry",["serial":current.serial,"attempt":waiting.wait.retries])
                return
            case .changed:
                if let opened=world.items[waiting.item.serial] { openedTravelDoors[opened.serial]=opened }
                travelDoor=nil; needsRouteRetry=true
                Telemetry.shared.record("travel_door_opened",["serial":waiting.item.serial])
            case .timedOut:
                cancelRoute()
                onInventoryMessage?("Travel stopped: the door did not open; it may be locked.")
                Telemetry.shared.record("travel_door_timeout",["serial":waiting.item.serial])
                return
            }
        }
        // Focus gates opportunistic gathering and direct input, not an explicit route.
        // Stop/manual input/disconnect still cancel travel through cancelRoute().
        if let waiting = waitingDoor {
            let result = waiting.wait.result(door:world.items[waiting.item.serial],at:ProcessInfo.processInfo.systemUptime)
            if result == .retry {
                var retry=waiting
                retry.wait.didRetry(at:ProcessInfo.processInfo.systemUptime); waitingDoor=retry
                connection.send(InteractionPackets.use(serial:waiting.item.serial))
                Telemetry.shared.record("door_route_retry",["serial":waiting.item.serial,"attempt":retry.wait.retries])
            } else if result == .changed {
                waitingDoor = nil
                Telemetry.shared.record("door_route_changed", ["serial":waiting.item.serial])
                onDoorOpenedRoute?(waiting.destination,waiting.remaining,waiting.running)
            } else if result == .timedOut {
                waitingDoor = nil
                onInventoryMessage?("The door did not open. It may be locked or inaccessible; route stopped.")
                Telemetry.shared.record("door_route_timeout", ["serial":waiting.item.serial])
            }
        }
        let routeNow=ProcessInfo.processInfo.systemUptime
        routeRecovery.expire(at:routeNow)
        if needsRouteRetry, routeNow>=routeRecovery.retryAt, !movement.awaitingPosition, let serial = playerSerial, let player = world.mobiles[serial] {
            needsRouteRetry = false; detourItem=nil; detourArrivedAt=nil
            let start = WalkPoint(x:player.x,y:player.y,z:player.z)
            if let route = routeResolver?(start,routeRecovery.blocked) {
                walkRoute = route; onWalkRoute?(route)
                Telemetry.shared.record("walk_route_replanned",["attempt":routeRecovery.attempts,"steps":route.count])
            } else if routeRecovery.hasTemporaryBlocks {
                needsRouteRetry=true // Keep the destination while an animal blocks a narrow passage.
                routeRecovery.waitForTemporaryBlocks()
            } else { cancelRoute(); onInventoryMessage?("No clear route around the obstruction.") }
        }
        if !needsRouteRetry, !movement.awaitingPosition, let serial = playerSerial, let player = world.mobiles[serial], var route = walkRoute {
            let current = WalkPoint(x:player.x,y:player.y,z:player.z)
            let enemies=world.mobiles.values.filter { $0.serial != serial && $0.isEnemy }
            if let detourItem {
                let item=world.items[detourItem]
                let target=item.map { WalkPoint(x:$0.x,y:$0.y,z:$0.z) } ?? current
                if autoPickup.mode == .off || !TravelSafety.pickupIsSafe(from:current,target:target,path:route,enemies:enemies) {
                    self.detourItem=nil; needsRouteRetry=true
                    Telemetry.shared.record("travel_pickup_abandoned",["reason":"safety_or_disabled"])
                    return
                }
            }
            if routeContinues,routeAction == nil,detourItem == nil,
               movement.pendingCount == 0,autoPickup.pending == nil,!inventoryRecoveryBusy,
               trade == nil,targetRequest == nil,combatTarget.serial == nil,
               routeNow >= nextDetourAt,routeNow-manualInventoryAt>2,
               let weight=characterStatus?.weight,let strength=characterStatus?.strength,
               weight<40+strength*7/2-10 {
                nextDetourAt=routeNow+1
                let candidates=world.items.values
                if let item=autoPickup.select(items:Array(candidates),player:player,at:routeNow,radius:6,portable:{
                    let unit=self.itemWeight?($0.graphic) ?? 255
                    return !self.detourAttempts.contains($0.serial) && unit<255 && weight+unit*max(1,$0.amount)<40+strength*7/2-10 &&
                        TravelSafety.pickupIsSafe(from:current,target:WalkPoint(x:$0.x,y:$0.y,z:$0.z),path:[],enemies:enemies)
                }),max(abs(item.x-player.x),abs(item.y-player.y))>1 {
                    if let path=pickupDetour?(current,item),!path.isEmpty,
                       TravelSafety.pickupIsSafe(from:current,target:WalkPoint(x:item.x,y:item.y,z:item.z),path:path,enemies:enemies) {
                        detourAttempts.insert(item.serial)
                        detourItem=item.serial; detourArrivedAt=nil; route=path; walkRoute=path; onWalkRoute?(path)
                        Telemetry.shared.record("travel_pickup_detour",["serial":item.serial,"steps":path.count])
                    }
                }
            }
            while route.first == current { route.removeFirst() }
            if walkRoute != route { onWalkRoute?(route) }
            walkRoute = route
            if let next = route.first {
                if routeContinues,let door=blockingTravelDoor?(current,next) {
                    guard movement.pendingCount == 0 else { return }
                    connection.send(InteractionPackets.use(serial:door.serial))
                    travelDoor=(door,DoorOpeningWait(door:door,at:routeNow))
                    Telemetry.shared.record("travel_door_requested",["serial":door.serial])
                    return
                }
                if let direction = WalkPath.direction(from:current,to:next) {
                    move(direction:direction | (routeRunning ? 0x80 : 0),routeStep:next)
                } else { cancelRoute() }
            } else if movement.pendingCount == 0 && !movement.awaitingPosition {
                if let item=detourItem {
                    if autoPickup.pending != nil { return }
                    // A previous confirmed pickup may still be in its short cooldown.
                    if detourArrivedAt == nil { detourArrivedAt=routeNow }
                    if world.items[item] != nil,routeNow-(detourArrivedAt ?? routeNow)<1 { return }
                    detourItem=nil; detourArrivedAt=nil; needsRouteRetry=true
                    Telemetry.shared.record("travel_pickup_resume",["serial":item])
                    return
                }
                if routeContinues {
                    guard routeSegments < 256, let next = routeResolver?(current,routeRecovery.blocked) else {
                        cancelRoute(); onInventoryMessage?("Unable to continue toward the map destination."); return
                    }
                    if !next.isEmpty {
                        routeSegments += 1; walkRoute = next; onWalkRoute?(next)
                        Telemetry.shared.record("walk_route_segment",["segment":routeSegments,"steps":next.count]); return
                    }
                }
                let action = routeAction; walkRoute = nil; routeAction = nil; onWalkRoute?([])
                dropGatheredDuringTravel=false
                if bankGatheredOnArrival {
                    bankGatheredOnArrival=false; bankingRequested=true; bankingCancelled=false
                }
                if !bankingRequested,let activity=travelActivity { ProcessInfo.processInfo.endActivity(activity); travelActivity=nil }
                if let action { performArrival(action, player: player) }
                Telemetry.shared.record("walk_route_completed")
            }
        }

    }
    private func performArrival(_ action:ArrivalAction, player:WorldMobile) {
        if case .openDoor(let planned,let destination,let remaining) = action {
            guard let current = world.items[planned.serial] else {
                onInventoryMessage?("The door is no longer nearby; route stopped."); return
            }
            if DoorOpeningWait.geometryChanged(from:planned,to:current) {
                // Somebody may already have opened it. Replan before sending
                // use, which is a toggle and could otherwise shut the doorway.
                Telemetry.shared.record("door_route_changed_during_approach",["serial":planned.serial])
                onDoorOpenedRoute?(destination,remaining,routeRunning)
                return
            }
        }
        if case .toolTarget(let request,let original,let tool) = action {
            guard targetRequest == request,equippedTargetTool == tool,
                  let held = world.equipment[tool],held.owner == player.serial,
                  held.layer == 1 || held.layer == 2 else {
                onInventoryMessage?("The tool or target request changed. Use the tool again."); return
            }
            let selection:TargetSelection
            if original.serial == 0 { selection = original }
            else if let mobile = world.mobiles[original.serial] {
                selection = TargetSelection(serial:mobile.serial,x:mobile.x,y:mobile.y,z:mobile.z,graphic:mobile.body)
            } else if let item = world.items[original.serial] {
                selection = TargetSelection(serial:item.serial,x:item.x,y:item.y,z:item.z,graphic:item.graphic)
            } else { onInventoryMessage?("That target is no longer nearby."); return }
            guard !ToolReach.needsApproach(playerX:player.x,playerY:player.y,target:selection) else {
                onInventoryMessage?("The target moved out of reach. Select it again."); return
            }
            target(selection,allowApproach:false)
            return
        }
        let target: WalkPoint?
        switch action {
        case .toolTarget: return
        case .attack(let serial):
            target = world.mobiles[serial].map { WalkPoint(x:$0.x,y:$0.y,z:$0.z) }
        case .openDoor(let door,_,_):
            target = world.items[door.serial].map { WalkPoint(x:$0.x,y:$0.y,z:$0.z) }
        case .use(let serial), .pickup(let serial,_):
            target = world.items[serial].map { WalkPoint(x:$0.x,y:$0.y,z:$0.z) }
        }
        guard let target, max(abs(target.x-player.x),abs(target.y-player.y)) <= 1,
              abs(target.z-player.z) <= 16 else {
            onInventoryMessage?("The target moved or is no longer within reach.")
            Telemetry.shared.record("arrival_action_out_of_range",["serial":action.serial]); return
        }
        switch action {
        case .toolTarget: return
        case .openDoor(let planned,let destination,let remaining):
            let serial = planned.serial
            guard let door = world.items[serial] else { return }
            use(serial:serial)
            waitingDoor = (door,destination,remaining,routeRunning,DoorOpeningWait(door:door,at:ProcessInfo.processInfo.systemUptime))
            onInventoryMessage?("Opening door…")
            Telemetry.shared.record("door_route_open_requested", ["serial":serial])
        case .use(let serial): use(serial:serial)
        case .pickup(let serial,let amount):
            guard let item = world.items[serial] else { return }
            pickupToBackpack(serial:serial,amount:min(amount,max(1,item.amount)))
        case .attack(let serial): attack(serial:serial)
        }
        Telemetry.shared.record("arrival_action_performed",["serial":action.serial])
    }
    private var staminaWalking = false
    func move(direction requestedDirection: UInt8, routeStep:WalkPoint? = nil) {
        let direction = MovementPace.direction(requestedDirection,stamina:characterStatus?.stamina)
        let walking = direction != requestedDirection
        if walking != staminaWalking {
            staminaWalking = walking
            Telemetry.shared.record("stamina_pace_changed",["walking":walking,"stamina":characterStatus?.stamina as Any? ?? NSNull()])
        }
        if routeStep == nil { cancelRoute() }
        guard loginComplete, let serial = playerSerial, let player = world.mobiles[serial] else { return }
        let delta = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)][Int(direction & 7)]
        let z = routeStep?.z ?? predictedElevation?(player.x + delta.0, player.y + delta.1, player.z)
        guard let packet = movement.request(direction: direction, player: player,
            at: ProcessInfo.processInfo.systemUptime, predictedZ: z), let predicted = movement.predictedPosition else { return }
        Telemetry.shared.record("move_request", ["direction": packet[1], "sequence": packet[2],
            "x": player.x, "y": player.y, "z": player.z, "predicted_x": predicted.x,
            "predicted_y": predicted.y, "predicted_z": predicted.z, "pending": movement.pendingCount])
        world.setPlayerPosition(predicted)
        onMobiles?(world.mobiles.values.sorted { $0.serial < $1.serial })
        onPlayer?(predicted)
        connection.send(packet)
    }

    func openBackpack() {
        guard let serial = playerSerial,
              let backpack = world.equipment.values.first(where: { $0.owner == serial && $0.layer == 21 }) else {
            Telemetry.shared.record("backpack_not_received")
            return
        }
        use(serial: backpack.serial)
    }
    private var awaitingSpellbook = false
    var onSpellbookOpened: ((UInt32,[ContainerItem])->Void)?
    private func availableSpellbook()->UInt32? {
        guard let playerSerial else { return nil }
        if let book = world.equipment.values.first(where: { $0.owner == playerSerial && $0.graphic == 0xEFA }) { return book.serial }
        guard let backpack = world.equipment.values.first(where: { $0.owner == playerSerial && $0.layer == 21 }) else { return nil }
        return world.containerItems.values.filter { $0.container == backpack.serial && $0.graphic == 0xEFA }.sorted { $0.serial < $1.serial }.first?.serial
    }
    func openSpellbook() {
        guard loginComplete else { return }
        if let serial = availableSpellbook() { use(serial:serial) }
        else { awaitingSpellbook = true; openBackpack() }
    }
    func castSpell(_ id:Int,book:UInt32) {
        guard loginComplete, ClassicSpells.contents(book:book,items:Array(world.containerItems.values)).contains(id),
              let packet = try? ClassicSpells.cast(id:id,book:book) else { return }
        cancelRoute(); equippedTargetTool = nil
        connection.send(packet)
        Telemetry.shared.record("spell_cast_requested",["id":id,"book":book])
    }
    private var death = DeathState()
    var onDeath: ((DeathState)->Void)?
    var onActionsCancelled: (() -> Void)?
    private func cancelActionsForDeath() {
        autoPickup.stop("Auto-pickup stopped because you died."); onAutoPickupMode?(0)
        cancelRoute(); movement = PlayerMovement()
        targetRequest = nil; equippedTargetTool = nil; equippedTargetDeadline = 0
        awaitingSpellbook = false; onTargeting?(false)
        combatTarget = CombatTarget(); onCombatTarget?(combatTarget)
        trade = nil; tradeTransfer = nil; onTrade?(nil)
        lastContainerContents = []; stagedVendorOffers = []; vendorOffers = []; vendorSerial = nil
        onVendorClosed?(); onActionsCancelled?()
        Telemetry.shared.record("death_actions_cancelled")
    }
    func respondToDeath(resurrect:Bool) {
        guard loginComplete, let packet = try? death.response(resurrect:resurrect) else { return }
        connection.send(packet); onDeath?(death)
        Telemetry.shared.record("death_response",["resurrect":resurrect])
    }
    private var textPrompt:TextPrompt?
    var onTextPrompt:((TextPrompt?)->Void)?
    func respondToPrompt(_ request:TextPrompt,text:String,accepted:Bool) {
        guard loginComplete,textPrompt == request,let packet = try? request.response(text:text,accepted:accepted) else { return }
        connection.send(packet); textPrompt = nil; onTextPrompt?(nil)
        Telemetry.shared.record("text_prompt_response",["accepted":accepted,"bytes":packet.count])
    }
    private var trade:SecureTrade?
    private var tradeTransfer:TradeTransfer?
    var onTrade:((SecureTrade?)->Void)?
    func acceptTrade(_ accepted:Bool,revision:UInt64) {
        guard loginComplete,var value = trade,let packet = try? value.setAccepted(accepted,revision:revision) else { return }
        trade = value; connection.send(packet); onTrade?(value)
        Telemetry.shared.record("trade_acceptance_requested",["accepted":accepted,"revision":revision])
    }
    func cancelTrade() {
        guard loginComplete,var value = trade,let packet = try? value.cancel() else { return }
        trade = value; connection.send(packet); onTrade?(value)
        Telemetry.shared.record("trade_cancel_requested")
    }
    private func updateTradeItems() {
        guard var value = trade else { return }
        if let revoke = value.update(items:Array(world.containerItems.values)) { connection.send(revoke); Telemetry.shared.record("trade_acceptance_revoked") }
        trade = value; onTrade?(value)
    }
    private var huePicker:HuePicker?
    var onHuePicker:((HuePicker?)->Void)?
    func chooseHue(_ hue:Int,request:HuePicker) {
        guard loginComplete, huePicker == request, let packet = try? request.response(hue:hue) else { return }
        connection.send(packet); huePicker = nil; onHuePicker?(nil)
        Telemetry.shared.record("hue_chosen",["serial":request.serial,"hue":hue])
    }
    private var serverGumps: [UInt64:ServerGump] = [:]
    var onServerGump: ((UInt64,ServerGump?)->Void)?
    func replyToGump(key:UInt64, definition:ServerGump, button:UInt32, switches:[UInt32], entries:[(UInt16,String)]) {
        guard loginComplete, serverGumps[key] == definition,
              let packet = try? definition.validatedResponse(button:button,switches:switches,entries:entries) else { return }
        connection.send(packet); serverGumps.removeValue(forKey:key); onServerGump?(key,nil)
        Telemetry.shared.record("gump_response",["id":definition.id,"button":button,"switches":switches.count,"entries":entries.count])
    }
    private var serverMenu:ServerMenu?
    var onServerMenu: ((ServerMenu?)->Void)?
    func chooseServerMenu(_ choice:Int) {
        guard loginComplete, let menu = serverMenu, let packet = try? menu.response(choice:choice) else { return }
        connection.send(packet); serverMenu = nil; onServerMenu?(nil)
        Telemetry.shared.record("server_menu_response",["serial":menu.serial,"id":menu.id,"choice":choice])
    }
    private var lastContainerContents: [ContainerItem] = []
    private var stagedVendorOffers: [VendorOffer] = []
    private var vendorOffers: [VendorOffer] = []
    private var vendorSerial: UInt32?
    private var vendorSelling = false
    var onVendor: ((UInt32, [VendorOffer], Bool) -> Void)?
    var onVendorClosed: (() -> Void)?
    func submitVendorTrade(_ quantities: [UInt32:Int]) -> String? {
        guard loginComplete, let vendorSerial else { return "Vendor session closed. Request stock again." }
        do {
            let packet = try vendorSelling ? VendorPackets.sell(vendor:vendorSerial,offers:vendorOffers,quantities:quantities) : VendorPackets.buy(vendor:vendorSerial,offers:vendorOffers,quantities:quantities)
            connection.send(packet)
            Telemetry.shared.record(vendorSelling ? "vendor_sell_requested" : "vendor_buy_requested",["vendor":vendorSerial,"lines":quantities.filter { $0.value > 0 }.count])
            return nil
        } catch {
            Telemetry.shared.record("vendor_trade_invalid",["selling":vendorSelling])
            return "Invalid trade selection. Clear it or request stock again."
        }
    }
    func closeVendor() {
        if let vendorSerial { connection.send(vendorSelling ? VendorPackets.cancelSell(vendor:vendorSerial) : VendorPackets.cancel(vendor:vendorSerial)) }
        vendorSerial = nil; vendorOffers = []; onVendorClosed?()
    }
    var onContainerOpened: ((OpenContainer) -> Void)?
    var onContainerItems: (([ContainerItem]) -> Void)?
    var onGroundObjects: (([GroundItem]) -> Void)?
    private var hoverInspection = HoverInspection()
    func inspect(serial: UInt32, automatic:Bool = false) {
        guard loginComplete else { return }
        if automatic && !hoverInspection.shouldRequest(serial,at:ProcessInfo.processInfo.systemUptime) { return }
        Telemetry.shared.record("inspect_object", ["serial": serial,"automatic":automatic])
        connection.send(InteractionPackets.inspect(serial: serial))
    }
    func use(serial: UInt32) {
        guard loginComplete,!inventoryRecoveryBusy else { return }
        autoPickup.relinquish(serial)
        if waitingDoor != nil { cancelRoute() }
        if case .toolTarget = routeAction { cancelRoute() }
        if let item = world.equipment[serial],item.owner == playerSerial,(item.layer == 1 || item.layer == 2) {
            equippedTargetTool = serial; equippedTargetDeadline = ProcessInfo.processInfo.systemUptime+10
        } else { equippedTargetTool = nil }
        Telemetry.shared.record("use_item", ["serial": serial])
        connection.send(InteractionPackets.use(serial: serial))
    }
    var onGraphicEffect: ((GraphicEffect)->Void)?
    var onAnimation: ((MobileAction)->Void)?
    var onMobileDeath: ((MobileDeath,WorldMobile,[EquippedItem])->Void)?
    func useEquippedTool() {
        guard loginComplete, let owner = playerSerial else { return }
        let hands = world.equipment.values.filter { $0.owner == owner && ($0.layer == 1 || $0.layer == 2) }
        // Prefer a tool over an off-hand shield; fall back to the main hand.
        let tools: Set<Int> = [0xE85,0xE86,0xF39,0xF3A,0xF43,0xF44,0xF45,0xF46,0xF47,0xF48,0xF49,0xF4A,0xF4B,0xF4C,0xF5E,0xF5F,0x13FA,0x13FB,0xE87,0xE88]
        let selected = hands.sorted { a,b in
            if tools.contains(a.graphic) != tools.contains(b.graphic) { return tools.contains(a.graphic) }
            return a.layer < b.layer
        }.first
        guard let selected else { onInventoryMessage?("Equip a tool, then press U to use it."); return }
        use(serial:selected.serial)
        Telemetry.shared.record("equipped_tool_shortcut",["serial":selected.serial,"graphic":selected.graphic])
    }
    private var equippedTargetTool:UInt32?
    private var equippedTargetDeadline:TimeInterval = 0
    var onApproachToolTarget:((TargetRequest,TargetSelection,UInt32)->Void)?
    private var targetRequest: TargetRequest?
    var onTargeting: ((Bool) -> Void)?
    var targeting: Bool { targetRequest != nil }
    func target(_ selection: TargetSelection?,allowApproach:Bool = true) {
        guard loginComplete, let request = targetRequest else { return }
        do {
            let response = try request.response(selection)
            if let selection,allowApproach,let tool = equippedTargetTool,
               let playerSerial,let player = world.mobiles[playerSerial],
               selection.serial == 0 || world.items[selection.serial] != nil || world.mobiles[selection.serial] != nil,
               ToolReach.needsApproach(playerX:player.x,playerY:player.y,target:selection) {
                onApproachToolTarget?(request,selection,tool)
                Telemetry.shared.record("tool_target_approach",["tool":tool,"x":selection.x,"y":selection.y])
                return
            }
            if case .toolTarget = routeAction { cancelRoute() }
            if selection == nil { equippedTargetTool = nil }
            connection.send(response)
            targetRequest = nil; equippedTargetTool = nil; onTargeting?(false)
            Telemetry.shared.record(selection == nil ? "target_cancelled" : "target_selected", ["cursor": request.cursor, "serial": selection?.serial ?? 0, "x":selection?.x ?? -1,"y":selection?.y ?? -1,"z":selection?.z ?? 0,"graphic":selection?.graphic ?? 0])
        } catch {
            Telemetry.shared.record("target_rejected_locally",["allows_location":request.allowsLocation,"serial":selection?.serial ?? 0,"graphic":selection?.graphic ?? 0])
            onInventoryMessage?("Select an object for this target.")
        }
    }
    func targetPaperdoll(serial:UInt32)->Bool {
        guard targeting,let playerSerial,let player = world.mobiles[playerSerial] else { return false }
        if serial == playerSerial {
            target(TargetSelection(serial:serial,x:player.x,y:player.y,z:player.z,graphic:player.body))
        } else if let item = world.equipment[serial],item.owner == playerSerial {
            target(TargetSelection(serial:serial,x:player.x,y:player.y,z:player.z,graphic:item.graphic))
        } else { return false }
        return true
    }
    func targetInventory(serial: UInt32) {
        guard let item = world.containerItems[serial] else { return }
        target(TargetSelection(serial: serial, x: item.x, y: item.y, z: 0, graphic: item.graphic))
    }
    private var lighting = WorldLighting()
    var onLighting:((WorldLighting)->Void)?
    var onMusic: ((Int)->Void)?
    var onSound: ((SoundEffect)->Void)?
    var onSpeech: ((SpeechMessage) -> Void)?
    func say(_ text: String) -> String? {
        guard loginComplete else { return "Connect before speaking." }
        do {
            let packet = try SpeechPackets.say(text)
            connection.send(packet)
            Telemetry.shared.record("speech_sent", ["bytes": packet.count,"type":packet[3]])
            return nil
        } catch { return String(describing: error) }
    }
    var onInventoryMessage: ((String) -> Void)?
    func pickupToBackpack(serial: UInt32, amount: Int) {
        guard let playerSerial, let backpack = world.equipment.values.first(where: { $0.owner == playerSerial && $0.layer == 21 }) else { return }
        guard world.containerItems[serial]?.container != backpack.serial else { return }
        Telemetry.shared.record("quick_pickup", ["serial": serial, "amount": amount])
        moveItem(serial: serial, amount: amount, x: 0xFFFF, y: 0xFFFF, target: backpack.serial)
    }
    func moveItem(serial: UInt32, amount: Int, x: Int, y: Int, target: UInt32, z: Int = 0) {
        guard autoPickup.pending == nil,!inventoryRecoveryBusy else { onInventoryMessage?("Waiting for automatic inventory transfer to finish."); return }
        autoPickup.relinquish(serial)
        manualInventoryAt=ProcessInfo.processInfo.systemUptime
        guard loginComplete, let playerSerial else { return }
        if var value = trade {
            let involved = target == value.ownContainer || value.items.contains { $0.serial == serial }
            if value.isOwnOffer(target) == false || value.isOwnOffer(serial) == false { return }
            if involved {
                guard !value.cancelling,!value.awaitingOfferUpdate,value.pendingAcceptance == nil else { return }
                if value.ownAccepted,let revoke = try? value.setAccepted(false,revision:value.revision) { trade = value; connection.send(revoke); onTrade?(value) }
            }
        }
        do {
            let packets = try world.movePackets(serial:serial,amount:amount,player:playerSerial,x:x,y:y,target:target,z:z)
            if var value = trade, value.isOwnOffer(target) == true || value.isOwnOffer(serial) == true {
                value.beginOfferChange(); trade = value; tradeTransfer = TradeTransfer(item:serial,destination:target); onTrade?(value)
            }
            for packet in packets { connection.send(packet) }
            Telemetry.shared.record("inventory_move", ["serial": serial, "amount": amount, "x": x, "y": y, "z":z, "target": target])
            onInventoryMessage?("Moving item…")
        } catch { Telemetry.shared.record("inventory_move_rejected_locally",["serial":serial,"amount":amount,"target":target]); onInventoryMessage?("Unable to move that item.") }
    }
    var equipmentLayer: ((Int) -> UInt8?)?
    func equipItemFromInventory(serial: UInt32) {
        guard let graphic = world.containerItems[serial]?.graphic ?? world.items[serial]?.graphic, let layer = equipmentLayer?(graphic) else { return }
        equipItem(serial: serial, layer: layer)
    }
    func equipItem(serial: UInt32, layer: UInt8) {
        guard autoPickup.pending == nil,!inventoryRecoveryBusy else { return }
        autoPickup.relinquish(serial)
        manualInventoryAt=ProcessInfo.processInfo.systemUptime
        guard trade?.isOwnOffer(serial) != false else { return }
        guard loginComplete, let owner = playerSerial, (world.containerItems[serial] != nil || world.items[serial] != nil) else { return }
        do {
            let equip = try InteractionPackets.equip(serial: serial, layer: layer, owner: owner)
            let pickup = try InteractionPackets.pickup(serial: serial, amount: 1)
            if var value = trade, value.isOwnOffer(serial) == true {
                guard !value.cancelling, !value.awaitingOfferUpdate, value.pendingAcceptance == nil else { return }
                if value.ownAccepted {
                    let revoke = try value.setAccepted(false,revision:value.revision)
                    connection.send(revoke)
                }
                value.beginOfferChange(); trade = value
                tradeTransfer = TradeTransfer(item:serial,destination:owner)
                onTrade?(value)
            }
            connection.send(pickup)
            connection.send(equip)
            onInventoryMessage?("Equipping item…")
            Telemetry.shared.record("inventory_equip", ["serial": serial, "layer": layer])
        } catch { onInventoryMessage?("That item cannot be equipped.") }
    }
    func removeEquipment(serial: UInt32) {
        guard autoPickup.pending == nil,!inventoryRecoveryBusy else { return }
        manualInventoryAt=ProcessInfo.processInfo.systemUptime
        guard loginComplete, let owner = playerSerial, let item = world.equipment[serial], item.owner == owner,
              EquipmentRules.isWearable(item.layer),
              let bag = world.equipment.values.first(where: { $0.owner == owner && $0.layer == 21 }) else { return }
        do {
            connection.send(try InteractionPackets.pickup(serial: serial, amount: 1))
            connection.send(try InteractionPackets.drop(serial: serial, x: 0xFFFF, y: 0xFFFF, container: bag.serial))
            onInventoryMessage?("Moving equipment to backpack…")
            Telemetry.shared.record("inventory_unequip", ["serial": serial, "layer": item.layer])
        } catch { onInventoryMessage?("Unable to remove equipment.") }
    }
    var onGroundItems: (([WorldTile]) -> Void)?
    var onMobiles: (([WorldMobile]) -> Void)?
    private enum Phase { case login, connecting, server, character, create, world }
    private var phase = Phase.login {
        didSet {
            artwork.shardSelection = phase == .server || (phase == .connecting && !choices.isHidden)
            account.isHidden = artwork.shardSelection; password.isHidden = artwork.shardSelection
            rememberPassword.isHidden = artwork.shardSelection
            action.imagePosition = .noImage
            action.image = nil; action.alternateImage = nil
            action.frame = NSRect(x:310,y:290,width:180,height:52)
            action.needsDisplay = true
            localLoginButton.isEnabled = phase == .login
            primaryLoginButton.isEnabled = phase == .login
        }
    }
    var onWorldEntry: ((WorldEntry) -> Void)?

    var onDismiss: (() -> Void)?

    init(assets: ClientAssets, loginDefaults:UserDefaults = UserDefaults(suiteName:"com.ultimaxb.UltimaMac")!, connection:GameConnection? = nil) {
        self.connection=connection ?? GameConnection()
        ClassicControlArt.install(assets)
        ClassicNativeFont.install(assets.fonts)
        choices=ClassicChoice(fonts:assets.fonts); cityChoice=ClassicChoice(fonts:assets.fonts)
        settings=ClassicPanel(assets:assets)
        localLoginButton=ClassicButton("Local Test Center",fonts:assets.fonts,target:nil,action:nil)
        primaryLoginButton=ClassicButton("Saved Server",fonts:assets.fonts,target:nil,action:nil)
        artwork = LoginArtwork(assets:assets)
        action = ClassicButton("Connect", fonts:assets.fonts, target:nil, action:nil)
        self.loginDefaults = loginDefaults
        self.savedLogin = SavedLogin(defaults:loginDefaults)
        characterSelection = CharacterSelectionPanel(assets: assets)
        characterCreation = CharacterCreationPanel(assets: assets)
        super.init(nibName: nil, bundle: nil)
        host.delegate = self; port.delegate = self; account.delegate = self
        host.stringValue = savedLogin.host
        port.stringValue = savedLogin.port
        account.stringValue = savedLogin.account
        rememberPassword.state = savedLogin.remembersPassword ? .on : .off
        password.stringValue = savedLogin.password() ?? ""
        view = LoginBackdrop()
        view.wantsLayer = true; view.layer?.backgroundColor = NSColor.black.cgColor
        artwork.translatesAutoresizingMaskIntoConstraints=false; view.addSubview(artwork)
        card.translatesAutoresizingMaskIntoConstraints=false; artwork.addSubview(card)
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant:640),artwork.heightAnchor.constraint(equalToConstant:480),
            artwork.centerXAnchor.constraint(equalTo:view.centerXAnchor),artwork.centerYAnchor.constraint(equalTo:view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo:artwork.leadingAnchor),card.trailingAnchor.constraint(equalTo:artwork.trailingAnchor),
            card.topAnchor.constraint(equalTo:artwork.topAnchor),card.bottomAnchor.constraint(equalTo:artwork.bottomAnchor)
        ])
        for (field,y) in [(account,140),(password,175)] {
            field.frame=NSRect(x:229,y:y,width:184,height:21)
            field.isBordered=false; field.isBezeled=false; field.drawsBackground=false
            field.font=ClassicNativeFont.uiFont; field.textColor=NSColor(calibratedRed:0.28,green:0.08,blue:0.06,alpha:1)
            card.addSubview(field)
        }
        account.setAccessibilityLabel("Account name"); password.setAccessibilityLabel("Password")
        account.placeholderAttributedString=NSAttributedString(string:"Account name",attributes:[.foregroundColor:NSColor.darkGray])
        password.placeholderAttributedString=NSAttributedString(string:"Password",attributes:[.foregroundColor:NSColor.darkGray])
        rememberPassword.title=""; rememberPassword.frame=NSRect(x:269,y:214,width:102,height:79)
        rememberPassword.setButtonType(.toggle); rememberPassword.image=artwork.image(0x41B); rememberPassword.alternateImage=artwork.image(0x41D)
        rememberPassword.imagePosition = .imageOnly; rememberPassword.isBordered=false
        rememberPassword.setAccessibilityLabel("Remember password in Keychain")
        rememberPassword.font=ClassicNativeFont.uiFont; card.addSubview(rememberPassword)
        let settingsButton=ClassicButton("Server & saved login",fonts:assets.fonts,target:self,action:#selector(toggleSettings))
        settingsButton.gemBackground=ClassicButton.sapphireGem
        settingsButton.frame=NSRect(x:140,y:372,width:230,height:42); card.addSubview(settingsButton)
        settings.frame=NSRect(x:105,y:100,width:430,height:250)
        settings.isHidden=true; card.addSubview(settings)
        localLoginButton.target=self; localLoginButton.action=#selector(quickLocalLogin)
        primaryLoginButton.target=self; primaryLoginButton.action=#selector(selectPrimaryLogin)
        primaryLoginButton.frame=NSRect(x:12,y:12,width:180,height:44)
        localLoginButton.frame=NSRect(x:210,y:12,width:205,height:44)
        primaryLoginButton.gemBackground=ClassicButton.sapphireGem
        localLoginButton.gemBackground=ClassicButton.sapphireGem
        settings.addSubview(primaryLoginButton); settings.addSubview(localLoginButton)
        for (label,field,y) in [("Server",host,80),("Port",port,125)] {
            let title=ClassicLabel(label,fonts:assets.fonts); title.frame=NSRect(x:16,y:y+6,width:65,height:24); settings.addSubview(title)
            field.frame=NSRect(x:80,y:y,width:335,height:30)
            field.isBezeled=false; field.isBordered=false; field.drawsBackground=true
            field.backgroundColor=NSColor(calibratedRed:0.76,green:0.71,blue:0.57,alpha:1); field.textColor = .black
            settings.addSubview(field)
        }
        let forget=ClassicButton("Forget saved password",fonts:assets.fonts,target:self,action:#selector(forgetPassword))
        forget.gemBackground=ClassicButton.sapphireGem
        forget.frame=NSRect(x:12,y:188,width:260,height:44); settings.addSubview(forget)
        let done=ClassicButton("Done",fonts:assets.fonts,target:self,action:#selector(toggleSettings))
        done.gemBackground=ClassicButton.sapphireGem
        done.frame=NSRect(x:295,y:188,width:120,height:44); settings.addSubview(done)
        choices.isHidden=true; choices.frame=NSRect(x:155,y:170,width:330,height:30); card.addSubview(choices)
        for control in [characterName,female,cityChoice] as [NSView] { control.isHidden=true; card.addSubview(control) }
        status.frame=NSRect(x:115,y:418,width:420,height:54); status.font=ClassicNativeFont.uiFont
        status.textColor=NSColor(calibratedRed:0.9,green:0.85,blue:0.7,alpha:1); card.addSubview(status)
        action.target=self; action.action=#selector(performAction)
        action.frame=NSRect(x:310,y:290,width:180,height:52)
        action.gemBackground=ClassicButton.sapphireGem
        action.isBordered=false; action.imagePosition = .noImage; action.setAccessibilityLabel("Connect or continue")
        card.addSubview(action)
        let disconnect=ClassicButton("Disconnect",fonts:assets.fonts,target:self,action:#selector(disconnect))
        disconnect.gemBackground=ClassicButton.sapphireGem
        disconnect.frame=NSRect(x:380,y:372,width:140,height:42); card.addSubview(disconnect)
        let close=ClassicButton("Back",fonts:assets.fonts,target:self,action:#selector(dismissOverlay))
        close.frame=NSRect(x:150,y:290,width:140,height:52)
        close.gemBackground=ClassicButton.sapphireGem
        card.addSubview(close)
        secondaryButtons=[disconnect,close,settingsButton]
        introControls.frame=NSRect(x:0,y:0,width:640,height:480); artwork.addSubview(introControls); introControls.isHidden=true
        for (id,selector,point) in [(0x3F3,#selector(enterLogin),NSPoint(x:256,y:190)),
                                   (0x3F9,#selector(introSettings),NSPoint(x:418,y:202)),
                                   (0x3FF,#selector(enterLogin),NSPoint(x:268,y:158)),
                                   (0x3FC,#selector(introInformation),NSPoint(x:260,y:133)),
                                   (0x3F6,#selector(enterLogin),NSPoint(x:148,y:202)),
                                   (0x402,#selector(quitClient),NSPoint(x:284,y:287))] {
            let button=NSButton(title:"",target:self,action:selector)
            button.image=artwork.image(id); button.alternateImage=artwork.image(id+1); button.imagePosition = .imageOnly; button.isBordered=false
            button.frame=NSRect(origin:point,size:button.image?.size ?? NSSize(width:60,height:24)); introControls.addSubview(button)
        }

        characterSelection.translatesAutoresizingMaskIntoConstraints = false
        characterSelection.isHidden = true; view.addSubview(characterSelection)
        NSLayoutConstraint.activate([
            characterSelection.widthAnchor.constraint(equalToConstant:448),
            characterSelection.heightAnchor.constraint(equalToConstant:430),
            characterSelection.centerXAnchor.constraint(equalTo:view.centerXAnchor),
            characterSelection.centerYAnchor.constraint(equalTo:view.centerYAnchor)
        ])
        characterCreation.translatesAutoresizingMaskIntoConstraints = false
        characterCreation.isHidden = true; view.addSubview(characterCreation)
        NSLayoutConstraint.activate([
            characterCreation.widthAnchor.constraint(equalToConstant:600),
            characterCreation.heightAnchor.constraint(equalToConstant:500),
            characterCreation.centerXAnchor.constraint(equalTo:view.centerXAnchor),
            characterCreation.centerYAnchor.constraint(equalTo:view.centerYAnchor)
        ])
        characterCreation.onBack = { [weak self] in
            guard let self, self.phase == .create else { return }
            self.showCharacterSelection()
        }
        characterCreation.onCreate = { [weak self] name, female, city, allocation, appearance in
            guard let self, self.phase == .create else { return }
            do {
                let packet = try LoginPackets.createCharacter(name:name,female:female,city:city,slot:self.creationSlot,allocation:allocation,appearance:appearance)
                self.characterDisplayName = name
                self.connection.send(packet); self.phase = .connecting; self.characterCreation.waiting()
                Telemetry.shared.record("character_creation_requested",["slot":self.creationSlot])
            } catch { self.reset("Character creation could not be sent.") }
        }
        characterSelection.onBack = { [weak self] in self?.disconnect() }
        characterSelection.onCreate = { [weak self] in self?.beginCreation() }
        characterSelection.onPlay = { [weak self] character in
            guard let self, self.phase == .character else { return }
            do {
                self.connection.send(try LoginPackets.play(name:character.name,slot:character.slot))
                self.characterDisplayName = character.name
                self.phase = .connecting; self.characterSelection.waiting("Entering the world…")
            } catch { self.characterSelection.update(self.characters,message:"Could not select that character.") }
        }
        characterSelection.onDelete = { [weak self] character in
            guard let self, self.phase == .character, self.pendingDeletion == nil else { return }
            do {
                let packet = try LoginPackets.deleteCharacter(slot:character.slot)
                self.pendingDeletion = character.slot
                self.characterSelection.waiting("Waiting for the server to delete the character…")
                self.connection.send(packet)
                Telemetry.shared.record("character_delete_confirmed",["slot":character.slot])
            } catch { self.characterSelection.update(self.characters,message:"Could not request deletion.") }
        }
        self.connection.onPacketMetadata = { outbound, opcode, count in
            Telemetry.shared.record(outbound ? "packet_sent" : "login_packet_received",
                ["opcode": String(format: "0x%02X", opcode), "bytes": count])
        }
        self.connection.onEvent = { [weak self] event in self?.handle(event) }

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func loadLoginProfile(_ profile:SavedLogin.Profile) {
        view.window?.makeFirstResponder(nil)
        savedLogin = SavedLogin(profile:profile,defaults:loginDefaults)
        host.stringValue = savedLogin.host; port.stringValue = savedLogin.port
        account.stringValue = savedLogin.account; password.stringValue = savedLogin.password() ?? ""
        rememberPassword.state = savedLogin.remembersPassword ? .on : .off
        host.isEditable = profile == .primary; port.isEditable = profile == .primary
        status.stringValue = profile == .local
            ? "Local Test Center · separate account and saved settings. New accounts are created on first login."
            : "Connect using your saved server settings."
        updateTabOrder(); view.window?.makeFirstResponder(account)
    }
    @objc private func quickLocalLogin() {
        guard phase == .login else { return }
        if savedLogin.profile != .local { loadLoginProfile(.local) }
        Telemetry.shared.record("login_profile_selected",["profile":"local"])
        if !account.stringValue.isEmpty && !password.stringValue.isEmpty { performAction() }
    }
    @objc private func selectPrimaryLogin() {
        guard phase == .login else { return }
        loadLoginProfile(.primary)
        Telemetry.shared.record("login_profile_selected",["profile":"primary"])
    }
    func controlTextDidChange(_ notification: Notification) {
        // A saved password must never follow an edited account/server tuple.
        password.stringValue = ""
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        if host.stringValue == savedLogin.host, port.stringValue == savedLogin.port, account.stringValue == savedLogin.account {
            password.stringValue = savedLogin.password() ?? ""
        }
    }
    @objc private func enterLogin() {
        introControls.isHidden=true; artwork.mainMenu=false; card.isHidden=false; artwork.showsForm=true
        updateTabOrder(); view.window?.makeFirstResponder(account)
    }
    @objc private func introSettings() { enterLogin(); showSettings(true) }
    @objc private func introInformation() { enterLogin(); status.stringValue="UltimaXB · Classic client assets · Swift macOS client" }
    @objc private func quitClient() { NSApplication.shared.terminate(nil) }
    private func showSettings(_ visible:Bool) {
        settings.isHidden = !visible
        if visible { card.addSubview(settings,positioned:.above,relativeTo:nil) }
        updateTabOrder(); focusVisibleControl()
    }
    @objc private func toggleSettings() { showSettings(settings.isHidden) }
    @objc private func performAction() {
        Telemetry.shared.record("login_action", ["phase": String(describing: phase)])
        do {
            switch phase {
            case .login:
                guard let number = UInt16(port.stringValue), number != 0,
                      !host.stringValue.isEmpty, !account.stringValue.isEmpty else {
                    status.stringValue = "Enter a server, valid port, and account name."
                    return
                }
                // Validate before persisting; nothing sensitive is included in telemetry.
                _ = try LoginPackets.account(name: account.stringValue, password: password.stringValue)
                let saved = savedLogin.save(host: host.stringValue, port: port.stringValue,
                    account: account.stringValue, password: password.stringValue, remember: rememberPassword.state == .on)
                Telemetry.shared.record("login_preferences_saved", ["remember_password": rememberPassword.state == .on,
                                                                    "keychain_status": saved])
                if saved != 0 {
                    status.stringValue = "Could not update Keychain (\(saved)). Uncheck Remember password to connect without saving."
                    return
                }
                framer = GamePacketFramer()
                try connection.login(host: host.stringValue, port: number,
                                     name: account.stringValue, password: password.stringValue)
                password.stringValue = ""
            case .server:
                guard servers.indices.contains(choices.indexOfSelectedItem) else { return }
                phase = .connecting
                action.isEnabled = false
                connection.selectServer(servers[choices.indexOfSelectedItem])
            case .create:
                guard cities.indices.contains(cityChoice.indexOfSelectedItem) else {
                    status.stringValue = "The server has not offered a starting city."
                    return
                }
                let packet = try LoginPackets.createCharacter(name: characterName.stringValue, female: female.state == .on,
                                                               city: cities[cityChoice.indexOfSelectedItem].index, slot: creationSlot)
                connection.send(packet)
                phase = .connecting
                action.isEnabled = false
                status.stringValue = "Creating character…"
            case .character:
                guard characters.indices.contains(choices.indexOfSelectedItem) else { return }
                let selected = characters[choices.indexOfSelectedItem]
                connection.send(try LoginPackets.play(name: selected.name, slot: selected.slot))
                phase = .connecting
                action.isEnabled = false
                status.stringValue = "Entering the world…"
            default: break
            }
        } catch { reset("Could not connect: \(error)") }
    }
    private func showCharacterSelection() {
        connection.finishWorldEntryWait()
        phase = .character
        characterCreation.isHidden = true
        card.isHidden = true; artwork.showsForm=false; characterSelection.isHidden = false
        characterSelection.update(characters,message:characters.isEmpty ? "Choose New to create a character." : "")
        updateTabOrder(); focusVisibleControl()
    }
    private func beginCreation() {
        guard phase == .character, let slot = CharacterList.firstEmptySlot(characters) else { return }
        creationSlot = slot; phase = .create
        characterSelection.isHidden = true; card.isHidden = true; artwork.showsForm=false
        characterCreation.isHidden = false; characterCreation.configure(cities:cities)
        updateTabOrder(); focusVisibleControl()
        Telemetry.shared.record("character_creation_opened",["slot":slot])
    }
    @objc private func forgetPassword() {
        let result = savedLogin.forget()
        password.stringValue = ""
        rememberPassword.state = .off
        Telemetry.shared.record("saved_password_forgotten", ["keychain_status": result])
        status.stringValue = result == 0 ? "Saved password removed." : "Could not remove saved password (\(result))."
    }
    func logout() { connection.disconnect() }
    @objc private func disconnect() { Telemetry.shared.record("disconnect_clicked"); connection.disconnect() }
    private func updateTabOrder() {
        // A manually inserted overlay does not automatically join the window's
        // original key-view loop. Keep its traversal separate from the world view.
        view.window?.autorecalculatesKeyViewLoop = false
        let controls=focusableControls(in:settings.isHidden ? view : settings)
        for index in controls.indices { controls[index].nextKeyView = controls[(index+1)%controls.count] }
    }
    private func focusableControls(in parent:NSView)->[NSView] {
        guard !parent.isHiddenOrHasHiddenAncestor else { return [] }
        if let field=parent as? NSTextField,field.isEditable,field.isEnabled { return [field] }
        if let button=parent as? NSButton,button.isEnabled { return [button] }
        return parent.subviews.flatMap { focusableControls(in:$0) }
    }
    private func focusVisibleControl() {
        view.window?.makeFirstResponder(focusableControls(in:settings.isHidden ? view : settings).first)
    }
    func show(in parent: NSView) {
        if view.superview !== parent {
            view.removeFromSuperview()
            view.frame = parent.bounds
            view.autoresizingMask = [.width, .height]
            parent.addSubview(view)
        }
        view.isHidden = false
        updateTabOrder()
        Telemetry.shared.record("login_shown")
        if phase == .login, password.stringValue.isEmpty,
           host.stringValue == savedLogin.host, port.stringValue == savedLogin.port, account.stringValue == savedLogin.account {
            password.stringValue = savedLogin.password() ?? ""
        }
        focusVisibleControl()
    }
    @objc private func dismissOverlay() {
        if !loginComplete {
            connection.disconnect(notify:false)
            reset("Connect using the 1.25.32 protocol.")
            card.isHidden=true; characterSelection.isHidden=true; characterCreation.isHidden=true
            introControls.isHidden=false; artwork.mainMenu=true; artwork.showsForm=false
            updateTabOrder(); focusVisibleControl()
            return
        }
        Telemetry.shared.record("login_dismissed", ["connected": loginComplete])
        view.window?.makeFirstResponder(nil)
        view.isHidden = true
        onDismiss?()
    }
    private func reset(_ message: String) {
        introControls.isHidden=true; artwork.mainMenu=false; settings.isHidden=true
        statusRefreshTask?.cancel(); statusRefreshTask = nil
        world = WorldState(); openedTravelDoors=[:]
        servers=[]; characters=[]; cities=[]; choices.removeAllItems(); cityChoice.removeAllItems()
        autoPickup = AutoPickup(); gatheredDrop=nil; awaitingDropWeight=nil; dropGatheredDuringTravel=false; banking=nil; bankingRequested=false; bankGatheredOnArrival=false; bankContentsContext=nil; bankTransferUntil=0; onAutoPickupMode?(0)
        hoverInspection = HoverInspection()
        lastContainerContents = []; stagedVendorOffers = []; vendorOffers = []; vendorSerial = nil; onVendorClosed?()
        pendingDeletion = nil; characterCreation.isHidden = true; characterSelection.isHidden = true; card.isHidden = false; artwork.showsForm=true
        skills = SkillState(); onSkills?(skills)
        characterStatus = nil; onCharacterStatus?(nil)
        lighting = WorldLighting(); onLighting?(lighting)
        combatTarget = CombatTarget(); onCombatTarget?(combatTarget)
        targetRequest = nil; onTargeting?(false)
        playerSerial = nil
        loginComplete = false
        movement = PlayerMovement(); cancelRoute()
        onPlayer?(nil)
        onEquipment?([])
        awaitingSpellbook = false
        equippedTargetTool = nil
        textPrompt = nil; onTextPrompt?(nil)
        trade = nil; tradeTransfer = nil; onTrade?(nil)
        huePicker = nil; onHuePicker?(nil)
        death = DeathState(); onDeath?(death)
        for key in serverGumps.keys { onServerGump?(key,nil) }; serverGumps.removeAll()
        serverMenu = nil; onServerMenu?(nil)
        openObjectWindows=OpenObjectWindows()
        onContainerItems?([])
        onGroundObjects?([])
        onGroundItems?([])
        onMobiles?([])
        phase = .login
        action.title = "Connect"
        action.isEnabled = true
        choices.isHidden = true
        characterName.isHidden = true
        female.isHidden = true
        cityChoice.isHidden = true
        status.stringValue = message
        updateTabOrder()
        if host.stringValue == savedLogin.host, port.stringValue == savedLogin.port, account.stringValue == savedLogin.account {
            password.stringValue = savedLogin.password() ?? ""
        }
    }
    private func handle(_ event: GameConnection.Event) {
        switch event {
        case .connecting:
            Telemetry.shared.record("connecting")
            phase = .connecting
            action.isEnabled = false
            status.stringValue = "Connecting…"
        case .servers(let entries):
            Telemetry.shared.record("server_list", ["count": entries.count])
            servers = entries
            phase = .server
            showChoices(entries.map(\.name), title: "Select Server")
        case .failed(let message): Telemetry.shared.record("connection_failed"); reset(message)
        case .disconnected: Telemetry.shared.record("disconnected"); reset("Disconnected.")
        case .gameData(let bytes):
            var packetContext = "framing \(bytes.count) received bytes"
            do {
                var changed = false
                var enteredWorld = false
                for packet in try framer.receive(bytes) {
                    packetContext = GamePacketDiagnostics.summary(packet)
                    let pickupPending=autoPickup.pending != nil
                    autoPickup.receive(packet)
                    gatheredDrop?.receive(packet)
                    if packet.first==0x27 || packet.first==0x28 {
                        let reason:UInt8? = packet.first==0x27 && packet.count>1 ? packet[1] : nil
                        banking?.refuse(reason:reason,time:ProcessInfo.processInfo.systemUptime)
                        if banking?.state == .retrying {
                            onInventoryMessage?("Server is busy; waiting before retrying bank deposit…")
                            Telemetry.shared.record("gathered_bank_retry_wait",["attempt":banking?.retryCount ?? 0,"reason":Int(reason ?? 0)])
                        }
                    }
                    if pickupPending && autoPickup.pending == nil {
                        onAutoPickupMode?(autoPickup.mode.rawValue)
                        onInventoryMessage?(autoPickup.stoppedReason ?? "Auto-pickup stopped.")
                        Telemetry.shared.record("auto_pickup_result",["outcome":autoPickup.mode == .off ? "stopped" : "skipped_refusal"])
                    }
                    Telemetry.shared.record("game_packet", ["opcode": String(format: "0x%02X", packet.first ?? 0), "bytes": packet.count])
                    if let previous = characterStatus {
                        var stats = previous
                        if try stats.apply(packet) {
                            if stats.needsDetailRefresh(after: previous, opcode: packet[0]) { scheduleStatusRefresh() }
                            characterStatus = stats; onCharacterStatus?(stats)
                            if packet[0]==0x11 { awaitingDropWeight=nil }
                            Telemetry.shared.record("player_status_updated", ["opcode": packet[0]])
                        }
                    }
                    let previousTarget = combatTarget.serial
                    if try combatTarget.apply(packet) {
                        onCombatTarget?(combatTarget)
                        Telemetry.shared.record("combat_target_updated",["serial":combatTarget.serial as Any? ?? NSNull(),"health":combatTarget.status?.health as Any? ?? NSNull(),"max_health":combatTarget.status?.maxHealth as Any? ?? NSNull()])
                        if let target = combatTarget.serial, previousTarget != target {
                            connection.send(CharacterStatus.request(serial:target))
                        }
                    }
                    let transferWasPending = tradeTransfer != nil
                    if var transfer = tradeTransfer {
                        try transfer.receive(packet)
                        tradeTransfer = transfer.complete ? nil : transfer
                        if transfer.complete { trade?.finishOfferChange() }
                    }
                    if packet.first == 0xAF {
                        let event = try MobileDeath.decode(packet)
                        if let mobile = world.mobiles[event.serial] {
                            onMobileDeath?(event,mobile,Array(world.equipment.values))
                        }
                        if case .attack(let serial) = routeAction, serial == event.serial { cancelRoute() }
                        Telemetry.shared.record("mobile_death",["serial":event.serial,"corpse":event.corpse,"alternate":event.alternate])
                    }
                    if try world.apply(packet) { changed = true; updateTradeItems() }
                    else if transferWasPending && tradeTransfer == nil { onTrade?(trade) }
                    invalidateInteractionObjects(world.removedObjects)
                    var invalidWindows=Set<UInt32>()
                    for serial in world.removedObjects { invalidWindows.formUnion(openObjectWindows.removed(serial)) }
                    if !invalidWindows.isEmpty { onObjectWindowsClosed?(invalidWindows) }
                    if let opcode = packet.first, [0x20, 0x77, 0x78].contains(opcode),
                       let serial = playerSerial {
                        let update = try WorldMobile.decode(packet)
                        if update.serial == serial, death.apply(player: update) {
                            if death.phase == .ghost { cancelActionsForDeath() }
                            else if death.phase == .alive {
                                // A route planned while dead may cross closed doors.
                                cancelRoute()
                            }
                            onDeath?(death)
                            Telemetry.shared.record("death_body_updated", ["body": update.body, "alive": death.phase == .alive])
                        }
                    }
                    let positionSerial = packet.first == 0x20 ? try WorldMobile.decode(packet).serial : nil
                    if let serial = playerSerial, let player = world.mobiles[serial],
                       packet.first == 0x21 || packet.first == 0x22 || positionSerial == serial {
                        if let moved = try movement.receive(packet, player: player) {
                            Telemetry.shared.record(packet.first == 0x21 ? "move_denied" : "move_accepted",
                                ["sequence": packet[1], "x": moved.x, "y": moved.y, "z": moved.z, "direction": moved.direction])
                            if let confirmed=movement.acknowledgedStep { routeRecovery.progress(confirmed) }
                            world.setPlayerPosition(moved)
                            changed = true
                            if packet.first == 0x21 {
                                let rejected=movement.rejectedStep
                                let mobileBlock = rejected.map { point in
                                    world.mobiles.values.contains { $0.serial != serial && !$0.isGhost &&
                                        $0.x == point.x && $0.y == point.y && abs($0.z-point.z)<16 }
                                } ?? false
                                let origin=WalkPoint(x:moved.x,y:moved.y,z:moved.z)
                                let now=ProcessInfo.processInfo.systemUptime
                                let doorBlocked = routeContinues && rejected.flatMap { blockingTravelDoor?(origin,$0) } != nil
                                let canRetry=walkRoute != nil && (doorBlocked ? routeRecovery.rejectWithoutStep(from:origin,at:now) : rejected.map {
                                    routeRecovery.reject($0,from:origin,temporary:mobileBlock,at:now)
                                } ?? routeRecovery.rejectWithoutStep(from:origin,at:now))
                                if canRetry {
                                    needsRouteRetry = true
                                    onWalkRoute?([])
                                    Telemetry.shared.record("walk_route_retry_pending",["attempt":routeRecovery.attempts,"mobile_attempt":routeRecovery.mobileAttempts,"temporary":mobileBlock,"has_rejected_step":rejected != nil,"x":rejected?.x as Any? ?? NSNull(),"y":rejected?.y as Any? ?? NSNull(),"z":rejected?.z as Any? ?? NSNull()])
                                } else { cancelRoute(); onInventoryMessage?("Movement was blocked; route stopped.") }
                                connection.send(movement.resynchronize(at:ProcessInfo.processInfo.systemUptime))
                            }
                        }
                    }
                    switch packet.first {
                    case 0x2C:
                        try death.apply(packet)
                        if death.phase == .offered {
                            cancelActionsForDeath()
                            onMusic?(42)
                        }
                        onDeath?(death)
                        Telemetry.shared.record("death_state",["alive":death.phase == .alive])
                    case 0x9A,0xAB:
                        let request = try TextPrompt.decode(packet)
                        textPrompt = request; cancelRoute(); onTextPrompt?(request)
                        Telemetry.shared.record("text_prompt_opened",["opcode":packet[0],"variant":request.variant,"limit":request.limit])
                    case 0x6F:
                        let event = try TradeEvent.decode(packet)
                        if let opened = SecureTrade(event:event) {
                            trade = opened; updateTradeItems(); cancelRoute()
                            Telemetry.shared.record("trade_opened")
                        } else if var value = trade {
                            value.apply(event); trade = value.closed ? nil : value; onTrade?(trade)
                            Telemetry.shared.record("trade_updated",["closed":value.closed,"own_accepted":value.ownAccepted,"other_accepted":value.otherAccepted])
                        }
                    case 0x95:
                        let request = try HuePicker.decode(packet)
                        huePicker = request; onHuePicker?(request)
                        Telemetry.shared.record("hue_picker_opened",["serial":request.serial,"type":request.typeID])
                    case 0xB0:
                        let gump = try ServerGump.decode(packet)
                        let key = UInt64(gump.serial) << 32 | UInt64(gump.id)
                        serverGumps[key] = gump; onServerGump?(key,gump)
                        Telemetry.shared.record("gump_opened",["id":gump.id,"commands":gump.commands.count,"texts":gump.texts.count])
                    case 0x7C:
                        let menu = try ServerMenu.decode(packet)
                        serverMenu = menu; onServerMenu?(menu)
                        Telemetry.shared.record("server_menu_opened",["serial":menu.serial,"id":menu.id,"options":menu.options.count,"icons":menu.usesIcons])
                    case 0x72:
                        if let serial = playerSerial, let player = world.mobiles[serial] {
                            let updated = try CombatPackets.applyMode(packet,to:player)
                            world.setPlayerPosition(updated); changed = true
                            Telemetry.shared.record("war_mode_received",["enabled":updated.flags & 0x40 != 0])
                        }
                    case 0x30, 0x31, 0xAA:
                        Telemetry.shared.record("combat_response",["opcode":packet[0],"length":packet.count])
                    case 0x3A:
                        try skills.apply(packet); onSkills?(skills)
                        Telemetry.shared.record("skills_received", ["count": skills.values.count])
                    case 0x4E,0x4F:
                        if try lighting.apply(packet,player:playerSerial) {
                            onLighting?(lighting)
                            Telemetry.shared.record("light_updated",["overall":lighting.overall,"personal":lighting.personal,"brightness":lighting.brightness])
                        }
                    case 0x6D:
                        let id = try MusicCatalog.decode(packet)
                        Telemetry.shared.record("music_received",["id":id]); onMusic?(id)
                    case 0x54:
                        let sound = try SoundEffect.decode(packet)
                        onSound?(sound)
                        Telemetry.shared.record("sound_received",["id":sound.id,"flags":sound.flags,"x":sound.x,"y":sound.y,"z":sound.z])
                    case 0x70:
                        let effect = try GraphicEffect.decode(packet)
                        onGraphicEffect?(effect)
                        Telemetry.shared.record("graphic_effect", ["kind":effect.kind.rawValue,"graphic":effect.graphic,
                            "duration_ms":Int(effect.duration*1000),"rendered_kind":effect.kind != .screen])
                    case 0x6E:
                        let animation = try MobileAction.decode(packet)
                        onAnimation?(animation)
                        Telemetry.shared.record("mobile_animation",["serial":animation.serial,"action":animation.action,"frames":animation.frameCount,"repeats":animation.repeatCount,"delay":animation.delay])
                    case 0x6C:
                        let request = try TargetRequest.decode(packet)
                        if case .toolTarget = routeAction { cancelRoute() }
                        if ProcessInfo.processInfo.systemUptime>equippedTargetDeadline || request.flags == 3 { equippedTargetTool = nil }
                        targetRequest = request.flags == 3 ? nil : request
                        onTargeting?(targetRequest != nil)
                        Telemetry.shared.record("target_requested", ["cursor": request.cursor, "flags": request.flags, "allows_location": request.allowsLocation])
                    case 0x1C:
                        let speech = try SpeechMessage.decode(packet)
                        if speech.serial == 0xFFFFFFFF && speech.text == "You must wait to perform another action." {
                            let now=ProcessInfo.processInfo.systemUptime
                            travelDoor?.wait.throttled(at:now); waitingDoor?.wait.throttled(at:now)
                            if travelDoor != nil || waitingDoor != nil {
                                Telemetry.shared.record("door_use_throttled")
                                onInventoryMessage?("Server is busy; waiting before trying the door again…")
                            }
                        }
                        onSpeech?(speech)
                        Telemetry.shared.record("speech_received", ["serial": speech.serial, "type": speech.type, "bytes": packet.count])
                    case 0x27, 0x28:
                        if packet[0] == 0x27 {
                            Telemetry.shared.record("inventory_rejected", ["opcode": packet[0], "reason": packet[1]])
                        } else {
                            Telemetry.shared.record("inventory_rejected", ["opcode": packet[0],
                                "x": Int(packet[1]) << 8 | Int(packet[2]),
                                "y": Int(packet[3]) << 8 | Int(packet[4])])
                        }
                        onInventoryMessage?("The server refused that move. The item remains where the server placed it.")
                    case 0x9E:
                        let result = try VendorPackets.sellOffers(packet)
                        vendorSerial = result.vendor; vendorOffers = result.offers; vendorSelling = true
                        stagedVendorOffers = []
                        onVendor?(result.vendor,result.offers,true)
                        Telemetry.shared.record("vendor_sell_list",["vendor":result.vendor,"count":result.offers.count])
                    case 0x74:
                        let offers = try VendorPackets.offers(packet,contents:lastContainerContents)
                        guard stagedVendorOffers.count+offers.count <= 500 else { throw LoginProtocolError.bufferLimit }
                        stagedVendorOffers += offers
                        Telemetry.shared.record("vendor_stock_received",["count":offers.count])
                        for offer in offers { Telemetry.shared.record("vendor_offer",["serial":offer.item.serial,"graphic":offer.item.graphic,"price":offer.price,"quantity":offer.item.amount]) }
                    case 0x3B:
                        let serial = try VendorPackets.closedVendor(packet)
                        if serial == vendorSerial { vendorSerial = nil; vendorOffers = []; onVendorClosed?() }
                    case 0x25, 0x3C:
                        if packet.first == 0x3C {
                            lastContainerContents = try ContainerItem.decode(packet)
                            let parents=Set(lastContainerContents.map(\.container))
                            if let root=bankContentsContext,
                               parents.isEmpty || parents == Set([root]) { banking?.contentsReceived(for:root,time:ProcessInfo.processInfo.systemUptime) }
                            bankContentsContext=nil
                            if awaitingSpellbook {
                                awaitingSpellbook = false
                                if let serial = availableSpellbook() { use(serial:serial) }
                                else { onInventoryMessage?("No spellbook was found in your backpack or equipment.") }
                            }
                        }
                        onInventoryMessage?("Inventory updated. Drag to move; drag a stack to split it.")
                    case 0x24:
                        if let container = world.openContainer {
                            bankContentsContext=container.serial
                            banking?.opened(container.serial,equipment:Array(world.equipment.values),time:ProcessInfo.processInfo.systemUptime)
                            if container.graphic != 0x30 { openObjectWindows.register(container.serial,world:world,player:playerSerial) }
                            if container.graphic == 0xFFFF {
                                onSpellbookOpened?(container.serial,Array(world.containerItems.values))
                                Telemetry.shared.record("spellbook_opened",["serial":container.serial])
                                break
                            }
                            if container.graphic == 0x30 {
                                vendorSelling = false; vendorSerial = container.serial; vendorOffers = stagedVendorOffers; stagedVendorOffers = []
                                onVendor?(container.serial,vendorOffers,false)
                            } else { onContainerOpened?(container) }
                        }
                    case 0xA9:
                        let list = try CharacterList.decode(packet)
                        Telemetry.shared.record("character_list", ["characters": list.characters.count, "cities": list.cities.count])
                        characters = list.characters
                        cities = list.cities
                        pendingDeletion = nil
                        showCharacterSelection()
                    case 0x86:
                        let list = try CharacterList.decodeUpdate(packet, cities:cities)
                        characters = list.characters; pendingDeletion = nil
                        showCharacterSelection()
                    case 0x85:
                        guard packet.count == 2 else { throw LoginProtocolError.malformedPacket }
                        if pendingDeletion != nil {
                            pendingDeletion = nil
                            let reasons = ["The character password was rejected.", "That character no longer exists.",
                                "That character is still logged in or waiting for logout.",
                                "The server requires the character to be at least seven days old.",
                                "The character is queued for backup. Try later.", "The server could not delete the character."]
                            characterSelection.update(characters,message:Int(packet[1]) < reasons.count ? reasons[Int(packet[1])] : "Deletion rejected (code \(packet[1])).")
                            Telemetry.shared.record("character_delete_rejected",["reason":packet[1]])
                        }
                    case 0x1B:
                        let entry = try WorldEntry.decode(packet)
                        Telemetry.shared.record("world_entry", ["x": entry.x, "y": entry.y, "z": entry.z, "body": entry.body])
                        onWorldEntry?(entry)
                        playerSerial = entry.serial
                        if let player = world.mobiles[entry.serial], death.apply(player: player) { onDeath?(death) }
                        characterStatus = CharacterStatus(serial: entry.serial)
                        characterCreation.isHidden = true; characterSelection.isHidden = true; card.isHidden = false; artwork.showsForm=true
                        phase = .world
                        choices.isHidden = true
                        characterName.isHidden = true
                        female.isHidden = true
                        cityChoice.isHidden = true
                        action.title = "Entering world…"
                        action.isEnabled = false
                        status.stringValue = "World position: \(entry.x), \(entry.y), \(entry.z). Body rendering is active; movement and clothing are pending."
                    case 0x55:
                        connection.finishWorldEntryWait()
                        Telemetry.shared.record("world_entry_complete")
                        loginComplete = true
                        requestStatus(); requestSkills()
                        enteredWorld = true
                        action.title = "Connected"
                    case 0x53, 0x82:
                        connection.disconnect(notify: false)
                        reset("Server rejected world entry (code \(packet.last ?? 0)).")
                    default: break
                    }
                }
                if let serial = playerSerial {
                    let evicted = world.pruneWorld(around: serial)
                    invalidateInteractionObjects(world.removedObjects)
                    var invalidWindows=Set<UInt32>()
                    for serial in world.removedObjects { invalidWindows.formUnion(openObjectWindows.removed(serial)) }
                    if !invalidWindows.isEmpty { onObjectWindowsClosed?(invalidWindows) }
                    if evicted > 0, let target = combatTarget.serial, world.mobiles[target] == nil {
                        combatTarget.clear(); onCombatTarget?(combatTarget)
                    }
                    if evicted > 0 {
                        changed = true
                        Telemetry.shared.record("world_cache_pruned", ["removed": evicted, "radius": 32])
                    }
                }
                let closedWindows=openObjectWindows.reconcile(world:world,player:playerSerial)
                if !closedWindows.isEmpty {
                    onObjectWindowsClosed?(closedWindows)
                    Telemetry.shared.record("object_windows_closed",["count":closedWindows.count,"reason":"out_of_reach"])
                }
                if changed {
                    Telemetry.shared.record("world_update", ["mobiles": world.mobiles.count, "ground_items": world.items.count, "equipment": world.equipment.count])
                    onEquipment?(Array(world.equipment.values))
                    onContainerItems?(Array(world.containerItems.values))
                    onGroundObjects?(world.groundObjects)
                    onGroundItems?(world.groundTiles)
                    onMobiles?(world.mobiles.values.sorted { $0.serial < $1.serial })
                }
                if let serial = playerSerial {
                    let stage = loginComplete ? "Connected" : "Waiting for world-entry completion"
                    if let player = world.mobiles[serial] {
                        onPlayer?(player)
                        if changed {
                            Telemetry.shared.record("player_state", ["x": player.x, "y": player.y, "z": player.z,
                                "body": player.body, "direction": player.direction,
                                "equipment": world.equipment.values.filter { $0.owner == serial }.sorted { $0.layer < $1.layer }.map {
                                    ["layer": Int($0.layer), "graphic": $0.graphic, "hue": $0.hue]
                                }])
                        }
                        status.stringValue = "\(stage). Player: \(player.x), \(player.y), \(player.z); body \(player.body). \(world.mobiles.count) mobiles, \(world.items.count) ground items."
                    } else {
                        status.stringValue = "\(stage). Player is absent from the current world state. \(world.mobiles.count) mobiles, \(world.items.count) ground items."
                    }
                }
                if enteredWorld { dismissOverlay() }
            } catch {
                Telemetry.shared.record("packet_error", ["context": packetContext, "error": String(describing: error)])
                connection.disconnect(notify: false)
                reset("Invalid game packet (\(packetContext)): \(error)")
            }
        }
    }
    private func showChoices(_ names: [String], title: String) {
        choices.removeAllItems()
        choices.addItems(withTitles: names)
        choices.isHidden = false
        action.title = title; action.setAccessibilityLabel(title)
        action.isEnabled = !names.isEmpty
        updateTabOrder()
        status.stringValue = "Choose an entry to continue."
        focusVisibleControl()
    }
}

// Consume pointer and keyboard input outside the card while login is visible.
@MainActor
private final class LoginBackdrop: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func mouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {}
}

@MainActor private final class FlippedLoginControls:NSView { override var isFlipped:Bool { true } }
