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
        print("Arrival routes cancel on target/tool removal, but not unrelated removals")
    }
}
