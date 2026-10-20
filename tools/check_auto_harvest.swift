import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let suite="com.ultimaxb.harvest.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defaults.set(false,forKey:"rememberPassword")
        defer { defaults.removePersistentDomain(forName:suite) }
        let transport=GameConnection()
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let login=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
        var now=ProcessInfo.processInfo.systemUptime
        login.harvestNow={now}
        func send(_ packet:Data) { transport.onEvent?(.gameData(packet)) }
        func speech(_ text:String,type:UInt8=6) {
            let bytes=Array(text.utf8)+[UInt8(0)],length=44+bytes.count
            send(Data([0x1C,UInt8(length>>8),UInt8(length&255),255,255,255,255,255,255,type,0,0,0,3])+Data(repeating:0,count:30)+Data(bytes))
        }
        func target(_ id:UInt32) { send(Data([0x6C,1])+Data(LoginPackets.seed(id))+Data([0])+Data(repeating:0,count:12)) }
        var entry=Data(repeating:0,count:37); entry[0]=0x1B; entry[4]=1
        entry.replaceSubrange(9..<18,with:[1,0x90,0,10,0,10,0,0,2])
        send(entry+Data([0x55]))
        var status=Data([0x11,0,66,0,0,0,1])+Data(repeating:0,count:30)
        status += Data([0,25,0,30,0,1,0,0,30,0,15,0,16,0,12,0,15,0,9,0,16,0,0,1,44,0,10,0,55])
        send(status)
        send(Data([0x2E,0x40,0,0,2,0x0E,0x75,0,21,0,0,0,1,0,0]))
        send(Data([0x2E,0x40,0,0,3,0x0E,0x85,0,1,0,0,0,1,0,0]))
        let zone=try HarvestWorkflow.Zone(x1:8,y1:8,x2:12,y2:12)
        let site=HarvestWorkflow.Site(target:.init(x:11,y:10,z:0,graphic:0x53B),standing:.init(x:10,y:10,z:0))
        var messages:[String]=[]
        login.onHarvestStatus={ messages.append($0) }
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.tickMovement()
        precondition(login.harvestActive && messages.last!.contains("Waiting for its contents"),"Unknown inventory waits without using the tool")
        send(Data([0x24,0x40,0,0,2,0,0x3C])); send(Data([0x3C,0,5,0,0]))
        // A remembered server attack object outside the work area is not
        // current nearby combat and must not permanently lock out harvesting.
        send(Data([0x77,0,0,0,9,0,0xD9,0,100,0,100,0,0,0,0,0,1]))
        send(Data([0xAA,0,0,0,9]))
        login.tickMovement() // Confirmed contents resume the accepted Start request.
        login.tickMovement()
        precondition(login.harvestActive && messages.last!.contains("Using tool"))
        precondition(!login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}),"A second Start cannot replace an outstanding tool request")
        let beforeOrdinarySpeech=messages.last
        speech("You must wait to perform another action.",type:0)
        precondition(messages.last == beforeOrdinarySpeech,"Ordinary speech cannot trigger automatic retries")
        speech("You must wait to perform another action.")
        precondition(messages.last!.contains("Server is busy"))
        now += 1.9; login.tickMovement()
        precondition(messages.last!.contains("Server is busy"))
        now += 0.2; login.tickMovement()
        precondition(messages.last!.contains("Using tool"))
        target(1)
        speech("You must wait to perform another action.")
        precondition(messages.last!.contains("Using tool"),"Post-target feedback must not replay the tool")
        precondition(!login.targeting,"Automated cursor must be answered once without exposing manual targeting")
        speech("You dig some ore and put it in your backpack.")
        login.tickMovement()
        precondition(!messages.contains(where:{$0.contains("1 successful")}),"Speech alone cannot confirm a resource gain")
        send(Data([0x25,0x40,0,0,4,0x19,0xB9,0,0,2,0,0,0,0,0x40,0,0,2,0,0]))
        login.tickMovement()
        precondition(messages.last!.contains("1 successful"),"Inventory update completes the correlated harvest attempt")
        now += 1.05; login.tickMovement(); target(2)
        speech("There is no metal here to mine.")
        precondition(!login.harvestActive && messages.last!.contains("finished"))
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.tickMovement(); login.stopHarvest(); target(3)
        precondition(!login.harvestActive && !login.targeting,"Stop cancels a late target instead of harvesting")
        precondition(!login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}),"Cannot reuse the late target window for a new run")
        now += 10.1
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.tickMovement(); login.useSkill(21)
        precondition(!login.harvestActive,"Manual skill use stops harvesting")
        now += 10.1
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        send(Data([0x77,0,0,0,9,0,0xD9,0,11,0,11,0,0,0,0,0,6]))
        login.tickMovement()
        precondition(!login.harvestActive && messages.last!.contains("danger"))
        precondition(!login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        precondition(messages.last!.contains("nearby combat target"),"A real nearby target must remain a visible start blocker")
        send(Data([0x1D,0,0,0,9])) // Remove the nearby hostile from the fixture.
        now += 10.1
        // A broken tool after a resolved dig must not immediately use its spare.
        login.equipmentLayer={_ in 1}
        send(Data([0x25,0x40,0,0,7,0x0E,0x85,0,0,1,0,0,0,0,0x40,0,0,2,0,0]))
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.tickMovement(); target(4)
        speech("You loosen some rocks but fail to find any useable ore.")
        // Removal follows the result in the same batch, as in live telemetry.
        send(Data([0x1D,0x40,0,0,3]))
        login.tickMovement()
        precondition(messages.last!.contains("Checking the backpack"))
        now += 0.9; login.tickMovement()
        precondition(messages.last!.contains("Checking the backpack"),"Spare equipment must wait for the action cooldown")
        now += 0.2; login.tickMovement()
        precondition(messages.last!.contains("Equipping"))
        send(Data([0x2E,0x40,0,0,7,0x0E,0x85,0,1,0,0,0,1,0,0]))
        login.tickMovement()
        precondition(messages.last!.contains("Using tool"),"Confirmed spare resumes after the pacing delay")
        login.stopHarvest()
        send(Data([0x1D,0x40,0,0,7]))
        send(Data([0x2E,0x40,0,0,3,0x0E,0x85,0,1,0,0,0,1,0,0]))
        now += 10.1
        login.equipmentLayer={_ in 2}
        func carriedAxe() { send(Data([0x25,0x40,0,0,5,0x0F,0x43,0,0,1,0,0,0,0,0x40,0,0,2,0,0])) }
        func equipAxe() { send(Data([0x2E,0x40,0,0,5,0x0F,0x43,0,2,0,0,0,1,0,0])) }
        carriedAxe()
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.lumberjacking,route:{_,_ in []}))
        precondition(login.harvestActive && messages.last!.contains("Equipping"))
        login.tickMovement()
        precondition(messages.last!.contains("Equipping"),"Do not use an unconfirmed equipped tool")
        equipAxe(); login.tickMovement()
        precondition(login.harvestActive && messages.last!.contains("Using tool"))
        login.stopHarvest(); now += 10.1
        carriedAxe()
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.lumberjacking,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:false)
        send(Data([0x27,0]))
        precondition(!login.harvestingSessionActive && messages.last!.contains("not confirmed"),"Refused equipment must end both harvesting and its forge circuit")
        login.tickMovement()
        precondition(!login.harvestingSessionActive && messages.last!.contains("not confirmed"),"The circuit must not replace the equip refusal with a stale workflow state")
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.lumberjacking,route:{_,_ in []}))
        login.stopHarvest(); equipAxe(); login.tickMovement()
        precondition(!login.harvestActive,"Late equip confirmation after Stop must not restart harvesting")
        now += 10.1
        send(Data([0x1A,0,14,0x40,0,0,9,0x0F,0xB1,0,11,0,10,0]))
        send(Data([0xAA,0,0,0,8])) // Historical target no longer in the streamed world.
        login.followRoute([],action:.smelt(0x40000009),running:false,resolver:{_,_ in []})
        login.tickMovement(); login.tickMovement()
        precondition(login.harvestActive && messages.last!.contains("Smelting ore"))
        speech("You must wait to perform another action.")
        precondition(messages.last!.contains("Server is busy"))
        now += 1.9; login.tickMovement()
        precondition(messages.last!.contains("Server is busy"))
        now += 0.2; login.tickMovement()
        precondition(messages.last!.contains("Smelting ore"))
        target(20)
        speech("You smelt the ore removing the impurities and put the metal in your backpack.")
        login.tickMovement()
        precondition(login.harvestActive,"Smelting speech alone cannot advance")
        send(Data([0x25,0x40,0,0,6,0x1B,0xF2,0,0,2,0,0,0,0,0x40,0,0,2,0,0]))
        login.tickMovement()
        precondition(!login.harvestActive && messages.last!.contains("Smelting finished: 1"))
        precondition(login.startSmelting(forge:0x40000009))
        login.tickMovement(); login.stopHarvest(); target(21)
        precondition(!login.harvestActive && !login.targeting,"Stop cancels smelting and its late cursor")
        login.followRoute([],action:.smelt(0x40000009),running:false,resolver:{_,_ in []})
        precondition(login.harvestActive)
        login.stopHarvest(); login.tickMovement()
        precondition(!login.harvestActive && messages.last!.contains("approach cancelled"))

        now += 10.1
        // A lost held pickaxe is replaced from a known bag inside the backpack.
        send(Data([0x25,0x40,0,0,8,0x0E,0x76,0,0,1,0,0,0,0,0x40,0,0,2,0,0]))
        send(Data([0x25,0x40,0,0,7,0x0E,0x85,0,0,1,0,0,0,0,0x40,0,0,8,0,0]))
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:false)
        send(Data([0x1D,0x40,0,0,3]))
        login.tickMovement(); now += 1.1; login.tickMovement()
        precondition(messages.last!.contains("Equipping") && login.harvestingSessionActive)
        send(Data([0x2E,0x40,0,0,7,0x0E,0x85,0,2,0,0,0,1,0,0]))
        login.tickMovement()
        precondition(messages.last!.contains("Using tool") && login.harvestingSessionActive)
        target(30); speech("There is no metal here to mine.")
        login.tickMovement()
        precondition(messages.last!.contains("Work zone finished"),"Replacement must preserve the circuit")
        precondition(!login.harvestingSessionActive)

        var trips:[WalkPoint]=[]
        var arrival:((Bool)->Void)?
        login.onMiningTravel={ point,_,done in trips.append(point); arrival=done }
        login.miningRoute={_,_,_ in []}
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:false)
        var heavy=status; heavy[64]=0; heavy[65]=140
        send(heavy); login.tickMovement()
        precondition(trips.count == 1 && trips[0].x == 11 && login.harvestingSessionActive)
        arrival?(true); login.tickMovement()
        precondition(messages.last!.contains("Smelting ore"))
        target(31)
        login.toggleHarvestPause()
        precondition(messages.last!.contains("Finishing the current ore"))
        speech("You smelt the ore removing the impurities and put the metal in your backpack.")
        login.tickMovement()
        precondition(trips.count == 1,"Wait for authoritative ingots before returning")
        send(Data([0x25,0x40,0,0,6,0x1B,0xF2,0,0,4,0,0,0,0,0x40,0,0,2,0,0]))
        send(status); login.tickMovement()
        now += 2; login.tickMovement()
        precondition(trips.count == 1 && messages.last!.contains("Smelting paused"),"Pause drains the current smelt and holds the return trip")
        login.toggleHarvestPause(); login.tickMovement()
        precondition(trips.count == 1,"Allow the completed smelt action to settle before mining again")
        now += 1.1; login.tickMovement()
        precondition(trips.count == 2 && trips[1].x == 10)
        arrival?(true); login.tickMovement()
        precondition(messages.last!.contains("cooldown"))
        now += 1.1; login.tickMovement(); login.tickMovement()
        precondition(messages.last!.contains("Using tool"),"Return resumes the saved mining site")
        login.stopHarvest()
        precondition(!login.harvestingSessionActive)

        now += 10.1
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:false)
        send(heavy); login.tickMovement()
        let staleArrival=arrival
        precondition(login.harvestingSessionActive)
        login.cancelRoute()
        send(status); staleArrival?(true); login.tickMovement()
        precondition(!login.harvestingSessionActive,"A late forge arrival cannot revive a cancelled circuit")

        var relocate:((HarvestWorkflow.Zone,[HarvestWorkflow.Site])->Void)?
        login.onMiningRelocate={_,_,used,done in
            precondition(used.contains("11,10,0,1339"))
            relocate=done
        }
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:true)
        login.tickMovement(); target(32); speech("There is no metal here to mine.")
        login.tickMovement()
        precondition(relocate != nil && login.harvestingSessionActive)
        relocate?(zone,[site]); login.tickMovement()
        precondition(messages.last!.contains("cooldown"))
        login.stopHarvest(); relocate?(zone,[site]); now += 2; login.tickMovement()
        precondition(!login.harvestingSessionActive,"Neither pending cooldown nor late zone result can restart mining after Stop")

        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:true)
        relocate=nil
        login.tickMovement(); login.toggleHarvestPause()
        precondition(messages.last!.contains("Pause requested"))
        target(33); speech("There is no metal here to mine.")
        login.tickMovement()
        precondition(relocate == nil,"Paused circuit must not relocate after its final tool response")
        precondition(!login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}),"Paused zone completion still owns the workflow")
        login.toggleHarvestPause(); login.tickMovement()
        precondition(relocate != nil,"Resume may advance a completed zone")
        relocate?(zone,[site]); login.tickMovement()
        precondition(messages.last!.contains("cooldown"),"A fresh zone cannot reset the tool cooldown")
        now += 0.9; login.tickMovement()
        precondition(messages.last!.contains("cooldown"))
        now += 0.2; login.tickMovement(); login.tickMovement()
        precondition(messages.last!.contains("Using tool"),"Mining resumes after the cross-zone cooldown")
        login.stopHarvest(); now += 10.1
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.toggleHarvestPause(); login.tickMovement()
        precondition(messages.last == "Harvesting paused.")
        now += 2; login.tickMovement()
        precondition(messages.last == "Harvesting paused.")
        login.toggleHarvestPause(); login.tickMovement()
        precondition(messages.last!.contains("Using tool"))
        login.stopHarvest()

        now += 10.1; trips=[]
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:false)
        send(heavy); login.tickMovement(); arrival?(true); login.tickMovement()
        target(34)
        speech("There is not enough metal-bearing ore in this pile to make an ingot.")
        send(status); login.tickMovement()
        now += 1.1; login.tickMovement()
        precondition(trips.count == 2,"Undersized leftovers should return to mining when carrying room exists")
        arrival?(true); login.tickMovement()
        precondition(messages.last!.contains("cooldown"))
        now += 1.1; login.tickMovement(); login.tickMovement()
        precondition(messages.last!.contains("Using tool"))
        login.stopHarvest()

        // Live regression: 14 small ore becomes 7 ingots, without success speech.
        now += 10.1; trips=[]
        send(Data([0x25,0x40,0,0,4,0x19,0xB7,0,0,14,0,0,0,0,0x40,0,0,2,0,0]))
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:false)
        send(heavy); login.tickMovement(); arrival?(true); login.tickMovement()
        target(37)
        send(Data([0x1D,0x40,0,0,4]))
        login.tickMovement()
        precondition(trips.count == 1,"Source removal alone cannot finish smelting")
        send(Data([0x25,0x40,0,0,6,0x1B,0xF2,0,0,11,0,0,0,0,0x40,0,0,2,0,0]))
        send(status); login.tickMovement(); now += 1.1; login.tickMovement()
        precondition(trips.count == 2,"Exact silent conversion must return to the mining zone")
        arrival?(true); login.tickMovement()
        precondition(messages.last!.contains("cooldown"))
        now += 1.1; login.tickMovement(); login.tickMovement()
        precondition(messages.last!.contains("Using tool"))
        login.stopHarvest()

        now += 10.1
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.tickMovement(); login.toggleWarMode()
        precondition(!login.harvestingSessionActive,"Manual war-mode toggle interrupts the tool workflow immediately")
        target(35)
        precondition(!login.targeting,"Late harvest cursor remains cancelled after a war-mode toggle")
        now += 10.1
        send(Data([0x77,0,0,0,1,1,0x90,0,10,0,10,0,2,0,0,0x40,1]))
        send(Data([0x77,0,0,0,9,0,0xD9,0,11,0,11,0,0,0,0,0,1]))
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.tickMovement(); login.attack(serial:9)
        precondition(!login.harvestingSessionActive,"Manual attack must not wait for a server combat-target response to stop harvesting")
        target(36); precondition(!login.targeting)
        // First-use smelting opens unknown inventory and resumes only while owned.
        for scenario in ["ready","cancelled","timeout","pauseTimeout"] {
            let freshTransport=GameConnection()
            let fresh=LoginOverlay(assets:assets,loginDefaults:defaults,connection:freshTransport)
            fresh.harvestNow={now}
            var result=""
            fresh.onHarvestStatus={result=$0}
            precondition(!fresh.startSmelting(forge:0x40000009) && result.contains("enter the world"))
            func packet(_ data:Data) { freshTransport.onEvent?(.gameData(data)) }
            packet(entry+Data([0x55]))
            precondition(!fresh.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}) && result.contains("strength and weight"))
            packet(status)
            precondition(!fresh.startSmelting(forge:0x40000009) && result.contains("no longer visible"))
            packet(Data([0x2E,0x40,0,0,2,0x0E,0x75,0,21,0,0,0,1,0,0]))
            packet(Data([0x1A,0,14,0x40,0,0,9,0x0F,0xB1,0,30,0,10,0]))
            precondition(!fresh.startSmelting(forge:0x40000009) && result.contains("out of reach"))
            packet(Data([0x1A,0,14,0x40,0,0,9,0x0F,0xB1,0,11,0,10,0]))
            precondition(fresh.startSmelting(forge:0x40000009))
            precondition(fresh.harvestActive && result.contains("Opening"))
            precondition(!fresh.startSmelting(forge:0x40000009),"Do not duplicate a pending backpack request")
            if scenario == "cancelled" { fresh.stopHarvest() }
            if scenario == "timeout" { now += 10.1; fresh.tickMovement() }
            packet(Data([0x24,0x40,0,0,2,0,0x3C]))
            packet(Data([0x3C,0,24,0,1,0x40,0,0,4,0x19,0xB7,0,0,14,0,0,0,0,0x40,0,0,2,0,0]))
            fresh.tickMovement()
            if scenario == "ready" {
                fresh.toggleHarvestPause(); now += 2; fresh.tickMovement()
                precondition(result.contains("Smelting paused"),"Pause before first use must hold the ready ore action")
                fresh.toggleHarvestPause(); fresh.tickMovement()
                precondition(fresh.harvestActive && result.contains("Smelting ore"),"Known inventory automatically resumes smelting")
            } else if scenario == "pauseTimeout" {
                fresh.tickMovement(); fresh.toggleHarvestPause()
                now += 11; fresh.tickMovement()
                precondition(!fresh.harvestActive && result.contains("timeout"),"Pause must not suppress a tool response timeout")
            } else {
                precondition(!fresh.harvestActive,"Late inventory cannot restart a cancelled or expired request")
            }
            fresh.stopHarvest()
        }
        for scenario in ["ready","cancelled","timeout","disconnected","bagRemoved"] {
            let transport=GameConnection()
            let fresh=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
            fresh.harvestNow={now}
            func packet(_ data:Data) { transport.onEvent?(.gameData(data)) }
            packet(entry+Data([0x55]));packet(status)
            packet(Data([0x2E,0x40,0,0,2,0x0E,0x75,0,21,0,0,0,1,0,0]))
            packet(Data([0x2E,0x40,0,0,3,0x0E,0x85,0,1,0,0,0,1,0,0]))
            var result=""
            fresh.onHarvestStatus={result=$0}
            precondition(fresh.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
            fresh.enableMiningCircuit(forge:.init(x:11,y:10,z:0),zone:zone,sites:[site],relocate:false)
            precondition(!fresh.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}),"Repeated Start cannot replace the pending inventory request")
            if scenario=="cancelled" { fresh.stopHarvest() }
            if scenario=="timeout" { now += 10.1;fresh.tickMovement() }
            if scenario=="disconnected" { transport.onEvent?(.disconnected) }
            if scenario=="bagRemoved" { packet(Data([0x1D,0x40,0,0,2]));fresh.tickMovement() }
            packet(Data([0x24,0x40,0,0,2,0,0x3C]));packet(Data([0x3C,0,5,0,0]))
            fresh.tickMovement();fresh.tickMovement()
            if scenario=="ready" {
                precondition(fresh.harvestingSessionActive && result.contains("Using tool"),"Confirmed inventory must resume mining and preserve its circuit")
            } else {
                precondition(!fresh.harvestingSessionActive,"Late inventory must not resurrect stopped mining")
            }
            fresh.stopHarvest()
        }
        print("Harvest adapter confirms resources, advances depleted sites, cancels late cursors and stops for manual actions/danger")
    }
}
