import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite="com.ultimaxb.arrival-check.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defaults.set(false,forKey:"rememberPassword")
        defer { defaults.removePersistentDomain(forName:suite) }
        let transport=GameConnection()
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let login=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
        // No transport connection exists: injected framing events exercise the
        // real route/invalidation adapter without sending to a server.
        transport.onEvent?(.gameData(Data([0x55])))
        var cancelled=0
        login.onRouteCancelled={cancelled += 1}
        let request=try TargetRequest.decode(Data([0x6C,1,0,0,0,1,0])+Data(repeating:0,count:12))
        let selection=TargetSelection(serial:50,x:10,y:10,z:0,graphic:1)
        let actions:[LoginOverlay.ArrivalAction] = [.pickup(50,1),.attack(50),.use(50),.toolTarget(request,selection,60)]
        for action in actions {
            login.followRoute([WalkPoint(x:10,y:10,z:0)],action:action,running:false,resolver:{_,_ in []})
            let before=cancelled
            transport.onEvent?(.gameData(Data([0x1D])+Data(LoginPackets.seed(99))))
            precondition(cancelled == before,"Unrelated removal must not cancel travel")
            transport.onEvent?(.gameData(Data([0x1D])+Data(LoginPackets.seed(50))))
            precondition(cancelled == before+1)
        }
        login.followRoute([WalkPoint(x:10,y:10,z:0)],action:.toolTarget(request,selection,60),running:false,resolver:{_,_ in []})
        let before=cancelled
        transport.onEvent?(.gameData(Data([0x1D])+Data(LoginPackets.seed(60))))
        precondition(cancelled == before+1,"Tool removal must cancel its approach")
        login.followRoute([WalkPoint(x:10,y:10,z:0)],action:nil,running:false,resolver:{_,_ in []})
        let travelCount=cancelled
        transport.onEvent?(.gameData(Data([0x1D])+Data(LoginPackets.seed(50))))
        precondition(cancelled == travelCount,"Ordinary travel has no object dependency")
        login.cancelRoute()
        func cursor(_ id:UInt32,flags:UInt8=0)->Data {
            Data([0x6C,1])+Data(LoginPackets.seed(id))+Data([flags])+Data(repeating:0,count:12)
        }
        var targetVisibility:[Bool]=[]
        login.onTargeting={targetVisibility.append($0)}
        transport.onEvent?(.gameData(cursor(7)))
        precondition(login.targeting)
        login.useSkill(-1)
        precondition(login.targeting,"An invalid action must preserve the current target")
        login.followRoute([WalkPoint(x:10,y:10,z:0)],action:.toolTarget(request,selection,60),running:false,resolver:{_,_ in []})
        let beforeSkill=cancelled
        login.useSkill(1)
        precondition(!login.targeting && cancelled==beforeSkill+1,"Changing skill clears the old cursor and approach immediately")
        transport.onEvent?(.gameData(cursor(8)))
        precondition(login.targeting && targetVisibility.last==true)
        precondition(login.use(serial:60))
        precondition(!login.targeting && targetVisibility.last==false,"Using another item clears the stale skill target")
        transport.onEvent?(.gameData(cursor(9)))
        login.followRoute([WalkPoint(x:10,y:10,z:0)],action:.toolTarget(request,selection,60),running:false,resolver:{_,_ in []})
        let beforeReplacement=cancelled
        transport.onEvent?(.gameData(cursor(10)))
        precondition(login.targeting && cancelled==beforeReplacement+1,"Replacement keeps the new cursor but cancels the old approach")
        transport.onEvent?(.gameData(cursor(10,flags:3)))
        precondition(!login.targeting && targetVisibility.last==false)
        transport.onEvent?(.gameData(cursor(11)))
        login.castSpell(1,book:0x40000007)
        precondition(login.targeting,"A spell absent from the book must not cancel the current target")
        transport.onEvent?(.gameData(Data([0x25,0x40,0,0,8,0x0F,0x2D,0,0,1,0,0,0,0])+Data(LoginPackets.seed(0x40000007))+Data([0,0])))
        login.castSpell(1,book:0x40000007)
        precondition(!login.targeting && targetVisibility.last==false,"An accepted spell selection clears the prior cursor")
        transport.onEvent?(.gameData(cursor(12)))
        precondition(login.targeting,"The next server cursor must still be accepted")
        transport.onEvent?(.disconnected)
        precondition(!login.targeting && targetVisibility.last==false)
        print("Arrival routes cancel on target/tool removal, but not unrelated removals")
    }
}
