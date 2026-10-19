import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let suite="com.ultimaxb.banking.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defaults.set(false,forKey:"rememberPassword")
        defer { defaults.removePersistentDomain(forName:suite) }
        let transport=GameConnection()
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let login=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
        var messages:[String]=[]
        login.onInventoryMessage={ messages.append($0) }
        func send(_ packet:Data) { transport.onEvent?(.gameData(packet)) }
        func equipment(_ serial:UInt32,_ layer:UInt8)->Data {
            Data([0x2E])+Data(LoginPackets.seed(serial))+Data([0x0E,0x75,0,layer,0,0,0,1,0,0])
        }
        func contents(_ amount:Int,_ bag:UInt32)->Data {
            Data([0x25,0x40,0,0,4,0x0F,0x7A,0,0,UInt8(amount),0,0,0,0])+Data(LoginPackets.seed(bag))+Data([0,0])
        }
        var entry=Data(repeating:0,count:37); entry[0]=0x1B; entry[4]=1
        entry.replaceSubrange(9..<18,with:[1,0x90,0,10,0,10,0,0,2])
        send(entry+Data([0x55]))
        var status=Data([0x11,0,66,0,0,0,1])+Data(repeating:0,count:30)
        status += Data([0,25,0,30,0,1,0, 0,30,0,15,0,16, 0,12,0,15,0,9,0,16, 0,0,1,44, 0,10,0,55])
        send(status); send(equipment(0x40000002,21))
        login.itemWeight={ _ in 1 }; login.setAutoPickup(1)
        // Two herbs on the player's tile, followed by the authoritative pickup.
        send(Data([0x1A,0,16,0xC0,0,0,4,0x0F,0x7A,0,2,0,10,0,10,0]))
        login.tickMovement()
        precondition(!login.use(serial:0x40000002),"Use must wait for a pending automatic pickup")
        login.equipItem(serial:0x40000004,layer:1)
        login.removeEquipment(serial:0x40000002)
        precondition(messages.filter { $0=="Waiting for automatic inventory transfer to finish." }.count==3)
        send(contents(2,0x40000002)); login.tickMovement()
        login.followRoute([],action:nil,running:false,resolver:{ _,_ in [] })
        login.bankGatheredOnArrival=true
        login.tickMovement(); login.tickMovement()
        precondition(messages.contains("Requesting your bank box…"))
        precondition(!login.use(serial:0x40000002),"Use must wait while bank deposits are active")
        // An unrelated open container must not start a deposit.
        send(Data([0x24,0x40,0,0,9,0,0x49])); send(Data([0x3C,0,5,0,0]))
        login.tickMovement()
        precondition(!messages.contains("Banking gathered goods…"))
        send(equipment(0x40000003,29))
        send(Data([0x24,0x40,0,0,3,0,0x49])); send(Data([0x3C,0,5,0,0]))
        login.tickMovement()
        precondition(!messages.contains("Banking gathered goods…"),"Opening the bank must allow a settling pause")
        Thread.sleep(forTimeInterval:1.05)
        login.tickMovement()
        precondition(messages.filter { $0=="Banking gathered goods…" }.count==1)
        login.tickMovement()
        precondition(messages.filter { $0=="Banking gathered goods…" }.count==1,"Do not resend an outstanding deposit")
        send(Data([0x27,255])); login.tickMovement()
        precondition(messages.contains("Server is busy; waiting before retrying bank deposit…"))
        precondition(messages.filter { $0=="Banking gathered goods…" }.count==1)
        Thread.sleep(forTimeInterval:2.05); login.tickMovement()
        precondition(messages.filter { $0=="Banking gathered goods…" }.count==2,"Retry explicit busy rejection after cooldown")
        send(contents(2,0x40000003))
        login.tickMovement(); Thread.sleep(forTimeInterval:1.05); login.tickMovement()
        precondition(messages.contains("Banked 2 gathered items. Confirmed transfers: 1. Existing belongings were kept."))
        // An empty subsequent arrival must not claim another successful deposit.
        login.followRoute([],action:nil,running:false,resolver:{ _,_ in [] })
        login.bankGatheredOnArrival=true
        login.tickMovement(); login.tickMovement()
        send(Data([0x24,0x40,0,0,3,0,0x49])); send(Data([0x3C,0,5,0,0]))
        login.tickMovement(); Thread.sleep(forTimeInterval:1.05); login.tickMovement()
        precondition(messages.contains("No gathered goods to deposit. Existing belongings were kept."))
        precondition(login.use(serial:0x40000002),"Use must resume once automatic transfers finish")
        send(contents(2,0x40000002))
        login.moveItem(serial:0x40000004,amount:2,x:0,y:0,target:0x40000003)
        precondition(messages.last=="Moving item…")
        precondition(!login.use(serial:0x40000002),"A second action must wait for the manual transfer")
        login.moveItem(serial:0x40000004,amount:2,x:0,y:0,target:0x40000003)
        precondition(messages.last=="Waiting for your previous item move to finish.")
        send(Data([0x1D])+Data(LoginPackets.seed(0x40000004)))
        precondition(!login.use(serial:0x40000002),"Removal is not a completed drop")
        send(contents(2,0x40000003))
        precondition(login.use(serial:0x40000002),"Authoritative placement releases the guard")
        login.moveItem(serial:0x40000004,amount:2,x:0,y:0,target:0x40000002)
        send(Data([0x27,255]))
        precondition(login.use(serial:0x40000002),"A refusal releases the manual guard without replay")
        login.moveItem(serial:0x40000004,amount:2,x:0,y:0,target:0x40000002)
        transport.onEvent?(.disconnected)
        send(entry+Data([0x55]))
        precondition(login.use(serial:0x40000002),"Reconnect must discard the previous transfer guard")
        print("Offline bank arrival, unrelated container rejection, single deposit and authoritative completion passed")
    }
}
