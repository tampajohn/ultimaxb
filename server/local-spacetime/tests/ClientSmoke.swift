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
        func returnDagger() throws {
            let packets = try world.movePackets(serial:daggerSerial,amount:1,player:1,x:65,y:65,target:0x40000100)
            transfer.begin(serial:daggerSerial,amount:1,destination:.container(0x40000100,x:65,y:65),world:world,time:0)
            inventoryStage = 2
            for outgoing in packets { client.send(outgoing) }
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
                        case 0x11:
                            var status = CharacterStatus(serial: 1)
                            try status.apply(packet)
                            guard status.health == 50 else { throw NSError(domain: "bad status", code: 1) }
                        case 0x78, 0x1a, 0x1d, 0x2e, 0x24, 0x25, 0x3c:
                            try world.apply(packet)
                            if packet[0] == 0x3c && inventoryStage == 0 {
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
                            guard message.type == 6 else { throw NSError(domain:"system speech type mismatch",code:1) }
                        case 0x55:
                            guard let entry = result else { throw NSError(domain: "missing entry", code: 1) }
                            guard world.equipment[0x40000100]?.layer == 21 else {
                                throw NSError(domain: "missing backpack equipment", code: 1)
                            }
                            guard world.items.values.contains(where: { $0.graphic == 0x9d0 && $0.amount == 2 }) else {
                                throw NSError(domain: "persisted ground stack quantity missing", code: 1)
                            }
                            client.send(Data([0x06,0x40,0x00,0x01,0x00]))
                            if !move { ready = true; break }
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
        guard ready, inventoryReady, let result else { throw NSError(domain: "smoke timeout", code: 1) }
        return result
    }

    @MainActor
    static func main() async throws {
        if CommandLine.arguments.count > 3 {
            let bytes = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))
            var framer=GamePacketFramer(), world=WorldState()
            var contents:[ContainerItem]=[], offers:[VendorOffer]=[], saleOffers:[VendorOffer]=[]
            for packet in try framer.receive(bytes) {
                switch packet[0] {
                case 0x78,0x24,0x3c:
                    try world.apply(packet)
                    if packet[0]==0x3c { contents=try ContainerItem.decode(packet) }
                case 0x74: offers=try VendorPackets.offers(packet,contents:contents)
                case 0x9e: saleOffers=try VendorPackets.sellOffers(packet).offers
                default: throw AssetError("Unexpected merchant packet")
                }
            }
            guard world.mobiles[2]?.body==400,world.openContainer?.graphic==0x30,
                  offers.count==1,offers[0].price==3,offers[0].item.graphic==0x9d0,
                  offers[0].item.amount==18 else { throw AssetError("Merchant stock or mobile decode failed") }
            let assets=try ClientAssets(directory:URL(fileURLWithPath:CommandLine.arguments[2]))
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
        print("PASS: real GameConnection, target/cancel, crafting and ingredient removal, crafted shield paperdoll/equipment, movement, reconnect")
    }
}
