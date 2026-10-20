import Foundation

// Compiled with the real UOCore sources into an isolated build directory.
@main
struct ClientSmoke {
    @MainActor
    static func session(port: UInt16, move: Bool) async throws -> WorldEntry {
        let client = GameConnection()
        defer { client.disconnect(notify: false) }
        var framer = GamePacketFramer()
        var result: WorldEntry?
        var failure: String?
        var ready = false
        var inventoryReady = false
        var smelt=SmeltWorkflow()
        var smelted = !move
        var lastSystemMessage = ""
        var skillState=SkillState()
        var receivedSkills=false
        var inventoryStage = 0
        var daggerSerial: UInt32 = 0
        var existingShields = Set<UInt32>()
        var craftedSerial: UInt32 = 0
        var transfer = ManualInventoryTransfer()
        var stage = 0
        var direction: UInt8 = 2
        var sequence: UInt8 = 0
        var expectedX = 0
        var expectedY = 0
        var expectedZ = 0
        var world = WorldState()
        let assets = try ClientAssets(directory: URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "uo1998-client"))
        for (id,name) in [(7,"Blacksmithy"),(11,"Carpentry"),(44,"Lumberjacking"),(45,"Mining")] {
            guard assets.skills.contains(where:{$0.id==id && $0.name==name}) else { throw AssetError("Installed skill definition mismatch") }
        }
        func returnDagger() throws {
            let packets = try world.movePackets(serial:daggerSerial,amount:1,player:1,x:65,y:65,target:0x40000100)
            transfer.begin(serial:daggerSerial,amount:1,destination:.container(0x40000100,x:65,y:65),world:world,time:0)
            inventoryStage = 2
            for outgoing in packets { client.send(outgoing) }
        }
        func beginMovement() throws {
            guard move,let entry=result else { return }
            let from = WalkPoint(x: entry.x, y: entry.y, z: entry.z)
            let map = try NavigationMap(assets: assets, center: from, additional: world.groundTiles)
            let candidates = (UInt8(0)...7).compactMap { d in map.step(from: from, direction: d).map { (d, $0) } }
            guard let choice = candidates.first(where: { $0.1.z != from.z }) ?? candidates.first else {
                throw NSError(domain: "no walkable neighboring tile", code: 1)
            }
            direction = choice.0
            expectedX = choice.1.x; expectedY = choice.1.y; expectedZ = choice.1.z
            stage = entry.direction & 7 == direction ? 2 : 1
            client.send(Data([0x02, direction, sequence]))
        }
        client.onEvent = { event in
            do {
                switch event {
                case .servers(let servers):
                    guard servers.count == 1, servers[0].name == "Local Spacetime" else {
                        throw NSError(domain: "unexpected shard list", code: 1)
                    }
                    client.selectServer(servers[0])
                case .failed(let message): failure = message
                case .gameData(let bytes):
                    for packet in try framer.receive(bytes) {
                        switch packet[0] {
                        case 0xa9:
                            let list = try CharacterList.decode(packet)
                            guard let character = list.characters.first else {
                                throw NSError(domain: "missing avatar", code: 1)
                            }
                            client.send(try LoginPackets.play(name: character.name, slot: character.slot))
                        case 0x1b:
                            result = try WorldEntry.decode(packet)
                            client.finishWorldEntryWait()
                        case 0x3a:
                            try skillState.apply(packet)
                            guard Set(skillState.values.keys)==Set([7,11,44,45]),skillState.values.values.allSatisfy({(0...1000).contains($0)}) else {
                                throw AssetError("Invalid skill values")
                            }
                            receivedSkills=true
                        case 0x11:
                            var status = CharacterStatus(serial: 1)
                            try status.apply(packet)
                            guard status.health == 50 else { throw NSError(domain: "bad status", code: 1) }
                        case 0x78, 0x1a, 0x1d, 0x2e, 0x24, 0x25, 0x3c:
                            try world.apply(packet)
                            if inventoryStage == -1 {
                                smelt.observe(world:world,time:ProcessInfo.processInfo.systemUptime)
                                if case .stopped(let reason)=smelt.state { throw AssetError("Smelt stopped: \(reason); \(lastSystemMessage)") }
                                if smelt.state == .completed {
                                    guard smelt.successes==1 else { throw AssetError("Smelt produced no ingots") }
                                    smelted=true; inventoryStage=0
                                }
                            }
                            if packet[0] == 0x3c && inventoryStage == 0 && !smelted {
                                guard let entry=result,let forge=world.items[0x40000003] else { throw AssetError("Missing nearby forge") }
                                try smelt.start(backpack:0x40000100,forge:forge,world:world)
                                let point=WalkPoint(x:entry.x,y:entry.y,z:entry.z)
                                guard case .useItem(let serial)=smelt.next(world:world,position:point,time:ProcessInfo.processInfo.systemUptime) else {
                                    throw AssetError("Smelt workflow could not start")
                                }
                                inventoryStage = -1
                                client.send(InteractionPackets.use(serial:serial))
                            } else if packet[0] == 0x3c && inventoryStage == 0 {
                                guard let dagger = world.containerItems.values.first(where: { $0.container == 0x40000100 && $0.graphic == 0xf51 && $0.amount == 1 }),
                                      try assets.equipmentLayer(graphic: dagger.graphic) == 1 else {
                                    throw NSError(domain: "missing persistent backpack contents", code: 1)
                                }
                                daggerSerial = dagger.serial
                                transfer.begin(serial:dagger.serial,amount:1,destination:.equipment(1,1),world:world,time:0)
                                inventoryStage = 1
                                client.send(try InteractionPackets.pickup(serial:dagger.serial,amount:1))
                                client.send(try InteractionPackets.equip(serial:dagger.serial,layer:1,owner:1))
                            } else if inventoryStage == 1, let outcome = transfer.receive(packet,world:world) {
                                guard outcome == .placed, world.equipment[daggerSerial]?.layer == 1 else {
                                    throw NSError(domain: "equipment transfer not confirmed", code: 1)
                                }
                                let layers = try Paperdoll.layers(assets:assets,body:400,hue:0x83ea,owner:1,equipment:Array(world.equipment.values))
                                guard layers.contains(where: { $0.item?.serial == daggerSerial }) else {
                                    throw NSError(domain: "equipped dagger has no paperdoll art", code: 1)
                                }
                                inventoryStage = 4
                                client.send(InteractionPackets.use(serial:daggerSerial))
                            } else if inventoryStage == 2, let outcome = transfer.receive(packet,world:world) {
                                guard outcome == .placed, world.containerItems[daggerSerial]?.container == 0x40000100,
                                      world.equipment[daggerSerial] == nil else {
                                    throw NSError(domain: "unequip transfer not confirmed", code: 1)
                                }
                                inventoryStage = 3; inventoryReady = true
                                try beginMovement()
                            } else if inventoryStage == 5, let shield = world.containerItems.values.first(where: {
                                $0.graphic == 0x1b7a && !existingShields.contains($0.serial)
                            }) {
                                guard !world.containerItems.values.contains(where: { $0.graphic == 0x1bdd }) else {
                                    throw NSError(domain:"craft left consumed logs in client state",code:1)
                                }
                                craftedSerial = shield.serial
                                transfer.begin(serial:shield.serial,amount:1,destination:.equipment(1,2),world:world,time:0)
                                inventoryStage = 6
                                client.send(try InteractionPackets.pickup(serial:shield.serial,amount:1))
                                client.send(try InteractionPackets.equip(serial:shield.serial,layer:2,owner:1))
                            } else if inventoryStage == 6, let outcome = transfer.receive(packet,world:world) {
                                guard outcome == .placed else { throw NSError(domain:"crafted shield equip failed",code:1) }
                                let layers = try Paperdoll.layers(assets:assets,body:400,hue:0x83ea,owner:1,equipment:Array(world.equipment.values))
                                guard layers.contains(where: { $0.item?.serial == craftedSerial }) else {
                                    throw NSError(domain:"crafted shield paperdoll art missing",code:1)
                                }
                                try returnDagger()
                            }
                        case 0x6c:
                            let request = try TargetRequest.decode(packet)
                            if inventoryStage == -1 {
                                guard let entry=result else { throw AssetError("Missing smelt position") }
                                let point=WalkPoint(x:entry.x,y:entry.y,z:entry.z)
                                guard case .target(let cursor,let selection)=smelt.receive(request,world:world,position:point,time:ProcessInfo.processInfo.systemUptime) else {
                                    throw AssetError("Smelt workflow rejected target")
                                }
                                client.send(try cursor.response(selection)); break
                            }
                            guard inventoryStage == 4,request.flags == 0,request.allowsLocation else {
                                throw NSError(domain:"unexpected target cursor",code:1)
                            }
                            if move {
                                guard let logs = world.containerItems.values.first(where: { $0.graphic == 0x1bdd && $0.amount == 5 }) else {
                                    throw NSError(domain:"missing persisted crafting ingredients",code:1)
                                }
                                existingShields = Set(world.containerItems.values.filter { $0.graphic == 0x1b7a }.map(\.serial))
                                existingShields.formUnion(world.equipment.values.filter { $0.graphic == 0x1b7a }.map(\.serial))
                                inventoryStage = 5
                                client.send(try request.response(.init(serial:logs.serial,x:logs.x,y:logs.y,z:0,graphic:logs.graphic)))
                            } else {
                                client.send(try request.response(nil))
                                try returnDagger()
                            }
                        case 0x1c:
                            let message = try SpeechMessage.decode(packet)
                            lastSystemMessage=message.text
                            guard message.type == 6 else { throw NSError(domain:"system speech type mismatch",code:1) }
                            if inventoryStage == -1 {
                                smelt.observe(speech:message,world:world,time:ProcessInfo.processInfo.systemUptime)
                            }
                        case 0x55:
                            guard result != nil else { throw NSError(domain: "missing entry", code: 1) }
                            guard world.equipment[0x40000100]?.layer == 21 else {
                                throw NSError(domain: "missing backpack equipment", code: 1)
                            }
                            guard world.items.values.contains(where: { $0.graphic == 0x9d0 && $0.amount == 2 }) else {
                                throw NSError(domain: "persisted ground stack quantity missing", code: 1)
                            }
                            client.send(SkillState.request(serial:1))
                            client.send(Data([0x06,0x40,0x00,0x01,0x00]))
                            if !move { ready = true; break }
                        case 0x22:
                            guard packet[1] == sequence else { throw NSError(domain: "bad movement ack", code: 1) }
                            sequence += 1
                            if stage == 1 {
                                stage = 2
                                client.send(Data([0x02, direction, sequence]))
                            } else {
                                stage = 3
                                client.send(PlayerMovement.requestPosition)
                            }
                        case 0x20:
                            let mobile = try WorldMobile.decode(packet)
                            if stage == 3 {
                                guard mobile.x == expectedX, mobile.y == expectedY, mobile.z == expectedZ else {
                                    throw NSError(domain: "wrong persisted movement", code: 1)
                                }
                                // Capture the confirmed position for reconnect comparison.
                                var entry = Data(repeating: 0, count: 37)
                                entry[0] = 0x1b
                                entry[4] = 1
                                entry[9] = 1; entry[10] = 0x90
                                entry[11] = UInt8(mobile.x >> 8); entry[12] = UInt8(mobile.x & 255)
                                entry[13] = UInt8(mobile.y >> 8); entry[14] = UInt8(mobile.y & 255)
                                entry[15] = mobile.z < 0 ? 255 : 0
                                entry[16] = UInt8(bitPattern: Int8(mobile.z))
                                entry[17] = mobile.direction
                                result = try WorldEntry.decode(entry)
                                ready = true
                            }
                        case 0x21: failure = "movement rejected"
                        case 0x27: failure = "inventory transfer rejected"
                        default: break
                        }
                    }
                default: break
                }
            } catch { failure = String(describing: error) }
        }
        try client.login(host: "127.0.0.1", port: port, name: "local", password: "local")
        for _ in 0..<1500 {
            if (ready && inventoryReady) || failure != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        if let failure { throw NSError(domain: failure, code: 1) }
        guard ready, inventoryReady, smelted, let result else { throw NSError(domain: "smoke timeout: inventory=\(inventoryStage), smelt=\(smelt.state), last=\(lastSystemMessage)", code: 1) }
        guard receivedSkills,skillState.values==[7:1,11:2,44:6,45:7] else {
            throw AssetError("Client skills did not persist or reflect completed actions: \(skillState.values)")
        }
        return result
    }

    @MainActor
    static func main() async throws {
        if CommandLine.arguments.count > 3 {
            let bytes = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))
            var framer=GamePacketFramer(), world=WorldState()
            var combat=CombatTarget()
            var sawCreatureHealth=false, sawDeath=false
            var contents:[ContainerItem]=[], offers:[VendorOffer]=[], saleOffers:[VendorOffer]=[]
            for packet in try framer.receive(bytes) {
                switch packet[0] {
                case 0x78,0x24,0x3c:
                    try world.apply(packet)
                    if packet[0]==0x3c { contents=try ContainerItem.decode(packet) }
                case 0xaa: _ = try combat.apply(packet)
                case 0x11:
                    _ = try combat.apply(packet)
                    sawCreatureHealth = combat.serial==3 && combat.status?.health==20
                case 0xaf:
                    guard try MobileDeath.decode(packet).serial==3 else { throw AssetError("Bad creature death") }
                    _ = try combat.apply(packet);try world.apply(packet);sawDeath=true
                case 0x74: offers=try VendorPackets.offers(packet,contents:contents)
                case 0x9e: saleOffers=try VendorPackets.sellOffers(packet).offers
                default: throw AssetError("Unexpected merchant packet")
                }
            }
            guard world.mobiles[2]?.body==400,world.openContainer?.graphic==0x30,
                  offers.count==1,offers[0].price==3,offers[0].item.graphic==0x9d0,
                  offers[0].item.amount==18 else { throw AssetError("Merchant stock or mobile decode failed") }
            let assets=try ClientAssets(directory:URL(fileURLWithPath:CommandLine.arguments[2]))
            for graphic in [0x9f1,0x9f2] {
                guard try assets.sprite(0x4000+graphic) != nil,
                      try assets.itemName(graphic:graphic).contains("ribs") else {
                    throw AssetError("Original rib art or tile name missing")
                }
            }
            guard sawCreatureHealth,sawDeath,combat.serial==nil,
                  try assets.animations?.frame(body:216,direction:3,action:2,frame:0) != nil,
                  try CorpseArt.frame(body:216,direction:3,assets:assets) != nil else {
                throw AssetError("Creature status, death, or original animation missing")
            }
            let layers=try Paperdoll.layers(assets:assets,body:400,hue:0x83ea,owner:2,equipment:Array(world.equipment.values))
            guard layers.filter({$0.item != nil}).count==3 else { throw AssetError("Merchant clothes missing original art") }
            let buy=try VendorPackets.buy(vendor:2,offers:offers,quantities:[offers[0].item.serial:2])
            guard buy.count==15,buy[0]==0x3b else { throw AssetError("Merchant purchase encoding failed") }
            guard saleOffers.count==1,saleOffers[0].price==1,saleOffers[0].item.amount==4 else {
                throw AssetError("Merchant sell offers failed")
            }
            let sell=try VendorPackets.sell(vendor:2,offers:saleOffers,quantities:[saleOffers[0].item.serial:2])
            guard sell.count==15,sell[0]==0x9f else { throw AssetError("Merchant sale encoding failed") }
            print("PASS: real UOCore merchant, clothing art, buy/sell prices and encoding")
        }
        let port = UInt16(CommandLine.arguments.dropFirst().first ?? "2594")!
        let moved = try await session(port: port, move: true)
        try await Task.sleep(for: .milliseconds(100))
        let resumed = try await session(port: port, move: false)
        guard moved.x == resumed.x, moved.y == resumed.y, moved.z == resumed.z, moved.direction == resumed.direction else {
            throw NSError(domain: "reconnect lost state", code: 1)
        }
        print("PASS: real GameConnection, SmeltWorkflow at persistent forge, target/cancel, crafting and ingredient removal, crafted shield paperdoll/equipment, movement, skills, reconnect")
    }
}
