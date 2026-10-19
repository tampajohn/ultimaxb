import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite="com.ultimaxb.mobile-route.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defaults.set(false,forKey:"rememberPassword")
        defer { defaults.removePersistentDomain(forName:suite) }
        let transport=GameConnection()
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let login=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
        // Offline transport: exercise real packet framing, prediction and recovery.
        var entry=Data(repeating:0,count:37)
        entry[0]=0x1B; entry[4]=1
        entry.replaceSubrange(9..<18,with:[1,0x90,0,10,0,10,0,0,2])
        transport.onEvent?(.gameData(entry+Data([0x55])))
        transport.onEvent?(.gameData(Data([0x77,0,0,0,2,0,0xD9,0,11,0,10,0,0,0,0,0,1])))
        let destination=WalkPoint(x:11,y:10,z:0)
        var cancelled=0, resolutions=0, playerX=10
        login.onRouteCancelled={cancelled += 1}
        login.onPlayer={playerX=$0?.x ?? -1}
        login.followRoute([destination],action:nil,running:false,resolver:{ start,blocked in
            precondition(start == WalkPoint(x:10,y:10,z:0))
            resolutions += 1
            return blocked.contains(destination) ? nil : [destination]
        })
        login.tickMovement()
        precondition(playerX == 11,"Initial step should predict immediately")
        transport.onEvent?(.gameData(Data([0x21,0,0,10,0,10,2,0])))
        precondition(playerX == 10 && cancelled == 0)
        transport.onEvent?(.gameData(Data([0x20,0,0,0,1,1,0x90,0,0,0,0,0,10,0,10,0,0,2,0])))
        login.tickMovement()
        precondition(playerX == 10 && resolutions == 0,"Pause must gate further prediction")
        Thread.sleep(forTimeInterval:0.8)
        login.tickMovement()
        precondition(cancelled == 0 && resolutions == 1 && playerX == 10,"No detour should wait, not cancel")
        login.tickMovement()
        precondition(resolutions == 1,"Waiting must not run the planner every frame")
        transport.onEvent?(.gameData(Data([0x1D,0,0,0,2])))
        Thread.sleep(forTimeInterval:1.3)
        login.tickMovement()
        precondition(cancelled == 0 && resolutions == 2 && playerX == 11,"Travel must resume through the cleared passage")
        login.cancelRoute()
        print("Mobile blockage preserves route, pauses prediction, bounds planning and resumes after expiry")
    }
}
