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
        func speech(_ text:String) {
            let bytes=Array(text.utf8)+[UInt8(0)],length=44+bytes.count
            send(Data([0x1C,UInt8(length>>8),UInt8(length&255),255,255,255,255,255,255,6,0,0,0,3])+Data(repeating:0,count:30)+Data(bytes))
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
        precondition(!login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}),"Require a known backpack baseline")
        send(Data([0x24,0x40,0,0,2,0,0x3C])); send(Data([0x3C,0,5,0,0]))
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}))
        login.tickMovement()
        precondition(login.harvestActive && messages.last!.contains("Using tool"))
        precondition(!login.startHarvest(zone:zone,sites:[site],kind:.mining,route:{_,_ in []}),"A second Start cannot replace an outstanding tool request")
        target(1)
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
        send(Data([0x1D,0,0,0,9])) // Remove the nearby hostile from the fixture.
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
        send(Data([0x27,0]))
        precondition(!login.harvestActive && messages.last!.contains("not confirmed"),"Refused equipment cannot start harvesting")
        precondition(login.startHarvest(zone:zone,sites:[site],kind:.lumberjacking,route:{_,_ in []}))
        login.stopHarvest(); equipAxe(); login.tickMovement()
        precondition(!login.harvestActive,"Late equip confirmation after Stop must not restart harvesting")
        now += 10.1
        send(Data([0x1A,0,14,0x40,0,0,9,0x0F,0xB1,0,11,0,10,0]))
        login.followRoute([],action:.smelt(0x40000009),running:false,resolver:{_,_ in []})
        login.tickMovement(); login.tickMovement()
        precondition(login.harvestActive && messages.last!.contains("Smelting ore"))
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
        print("Harvest adapter confirms resources, advances depleted sites, cancels late cursors and stops for manual actions/danger")
    }
}
