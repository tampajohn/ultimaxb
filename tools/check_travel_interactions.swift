import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let suite="com.ultimaxb.travel-interactions.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defaults.set(false,forKey:"rememberPassword")
        defer { defaults.removePersistentDomain(forName:suite) }
        let transport=GameConnection()
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let login=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
        func send(_ packet:Data) { transport.onEvent?(.gameData(packet)) }
        var entry=Data(repeating:0,count:37); entry[0]=0x1B; entry[4]=1
        entry.replaceSubrange(9..<18,with:[1,0x90,0,10,0,10,0,0,2])
        send(entry+Data([0x55]))
        let next=WalkPoint(x:11,y:10,z:0)
        send(Data([0x1A,0,14,0x40,0,0,4,0x06,0x75,0,11,0,10,0]))
        let door=login.routeItems.first { $0.serial==0x40000004 }!
        var playerX=10, cancelled=0, replans=0
        login.onPlayer={playerX=$0?.x ?? -1}; login.onRouteCancelled={cancelled += 1}
        login.blockingTravelDoor={ _,_ in door }
        login.followRoute([next],action:nil,running:false,continuing:true,resolver:{ _,_ in replans += 1; return [next] })
        login.bankGatheredOnArrival=true; login.dropGatheredDuringTravel=true
        login.tickMovement(); login.tickMovement()
        precondition(playerX==10 && replans==0 && cancelled==0,"Wait for door update without walking through it")
        precondition(login.bankGatheredOnArrival && login.dropGatheredDuringTravel,"Door use must retain travel options")
        let text=Array("You must wait to perform another action.".utf8)+[UInt8(0)]
        let length=44+text.count
        send(Data([0x1C,UInt8(length>>8),UInt8(length&255),255,255,255,255,255,255,6,0,0,0,3])+Data(repeating:0,count:30)+Data(text))
        login.tickMovement()
        precondition(playerX==10 && cancelled==0,"Throttle must wait without discarding the journey")
        Thread.sleep(forTimeInterval:2.05); login.tickMovement()
        precondition(playerX==10 && login.bankGatheredOnArrival,"Retry must still wait for actual door change")
        send(Data([0x1A,0,14,0x40,0,0,4,0x06,0x76,0,11,0,11,0]))
        login.blockingTravelDoor={ _,_ in nil }
        login.tickMovement()
        precondition(playerX==11 && replans==1 && cancelled==0,"Confirmed door update resumes original planner")
        precondition(login.bankGatheredOnArrival,"Bank option must survive replan")
        let opened=login.routeItems.first { $0.serial==0x40000004 }!
        precondition(login.travelDoorAlreadyChanged(opened),"Updated door must not be toggled again")
        precondition(login.travelDoorObstacles.contains(WalkPoint(x:11,y:11,z:0)))
        login.cancelRoute()
        precondition(login.travelDoorAlreadyChanged(opened),"Restarting travel must remember the opened door")

        // Reset the authoritative player position before testing opportunistic detours.
        send(Data([0x20,0,0,0,1,1,0x90,0,0,0,0,0,10,0,10,0,0,2,0]))
        var status=Data([0x11,0,66,0,0,0,1])+Data(repeating:0,count:30)
        status += Data([0,25,0,30,0,1,0,0,30,0,15,0,16,0,12,0,15,0,9,0,16,0,0,1,44,0,10,0,55])
        send(status)
        send(Data([0x2E,0x40,0,0,2,0x0E,0x75,0,21,0,0,0,1,0,0]))
        send(Data([0x1A,0,16,0xC0,0,0,8,0x0F,0x7A,0,2,0,13,0,10,0]))
        login.itemWeight={ _ in 1 }; login.setAutoPickup(1)
        var detours=0
        login.pickupDetour={ start,item in
            precondition(start.x==10 && item.serial==0x40000008)
            detours += 1; return [WalkPoint(x:11,y:10,z:0),WalkPoint(x:12,y:10,z:0)]
        }
        // Enemy nearby must suppress detours despite a visible eligible herb.
        send(Data([0x77,0,0,0,2,0,0xD9,0,12,0,12,0,0,0,0,0,6]))
        login.followRoute([next],action:nil,running:false,continuing:true,resolver:{ _,_ in [next] })
        login.tickMovement()
        precondition(detours==0,"Nearby enemies suppress pickup detours")
        login.cancelRoute()
        send(Data([0x1D,0,0,0,2]))
        send(Data([0x20,0,0,0,1,1,0x90,0,0,0,0,0,10,0,10,0,0,2,0]))
        // An enemy still visible eleven tiles away does not veto a short pickup.
        send(Data([0x77,0,0,0,3,0,0xD9,0,21,0,10,0,0,0,0,0,6]))
        login.followRoute([next],action:nil,running:false,continuing:true,resolver:{ _,_ in [next] })
        login.bankGatheredOnArrival=true
        login.tickMovement()
        precondition(detours==1 && login.bankGatheredOnArrival,"Safe visible pickup starts a detour without losing bank intent")
        login.cancelRoute()
        // Keep a movement request outstanding as new items enter view. Scanning
        // must drain the queue, then try beyond an unreachable nearest item.
        send(Data([0x1D,0x40,0,0,8])); send(Data([0x1D,0,0,0,3]))
        send(Data([0x20,0,0,0,1,1,0x90,0,0,0,0,0,10,0,10,0,0,2,0]))
        Thread.sleep(forTimeInterval:0.45)
        login.followRoute([next,WalkPoint(x:12,y:10,z:0)],action:nil,running:false,continuing:true,resolver:{ _,_ in [next] })
        login.tickMovement()
        precondition(playerX==11)
        send(Data([0x1A,0,16,0xC0,0,0,7,0x0F,0x7A,0,2,0,14,0,10,0]))
        send(Data([0x1A,0,16,0xC0,0,0,8,0x0F,0x7A,0,2,0,15,0,10,0]))
        var tried:[UInt32]=[]
        login.pickupDetour={ start,item in
            tried.append(item.serial)
            if item.serial==0x40000007 { return nil }
            return [WalkPoint(x:12,y:10,z:0),WalkPoint(x:13,y:10,z:0)]
        }
        Thread.sleep(forTimeInterval:1.05); login.tickMovement()
        precondition(tried.isEmpty && playerX==11,"Wait for movement confirmation instead of adding steps past the loot")
        send(Data([0x20,0,0,0,1,1,0x90,0,0,0,0,0,11,0,10,0,0,2,0]))
        login.tickMovement()
        precondition(tried == [0x40000007,0x40000008],"An unreachable nearest item must not starve the next candidate")
        login.cancelRoute()
        print("Travel door waits, threat clearance, movement settling and alternate pickup candidates passed")
    }
}
