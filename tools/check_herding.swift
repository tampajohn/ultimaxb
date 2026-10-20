import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let suite="com.ultimaxb.herding.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        // Isolated defaults with no saved credentials or network connection.
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(false,forKey:"rememberPassword")
        let transport=GameConnection(),login=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
        var now=ProcessInfo.processInfo.systemUptime
        login.harvestNow={now}; login.equipmentLayer={_ in 2}
        var message=""
        login.onHarvestStatus={message=$0}
        func send(_ packet:Data) { transport.onEvent?(.gameData(packet)) }
        func animal(x:UInt8=11,y:UInt8=10,z:UInt8=0) { send(Data([0x77,0,0,0,9,0,0xD9,0,x,0,y,z,0,0,0,0,1])) }
        func cursor(location:UInt8) { send(Data([0x6C,location,0,0,0,7,0])+Data(repeating:0,count:12)) }
        func speech(_ text:String,ordinary:Bool=false) {
            let bytes=Array(text.utf8)+[UInt8(0)],length=44+bytes.count
            send(Data([0x1C,UInt8(length>>8),UInt8(length&255),255,255,255,255,255,255,ordinary ? 0:6,0,0,0,3])+Data(repeating:0,count:30)+Data(bytes))
        }
        var entry=Data(repeating:0,count:37); entry[0]=0x1B; entry[4]=1
        entry.replaceSubrange(9..<18,with:[1,0x90,0,10,0,10,0,0,2]); send(entry+Data([0x55]))
        send(Data([0x2E,0x40,0,0,2,0x0E,0x75,0,21,0,0,0,1,0,0]))
        send(Data([0x2E,0x40,0,0,3,0x0E,0x81,0,2,0,0,0,1,0,0]))
        animal()
        let destination=WalkPoint(x:10,y:11,z:0)
        func start() { precondition(login.startHerding(animal:9,destination:destination)) }
        start(); login.tickMovement()
        precondition(message.contains("waiting to select") && login.harvestingSessionActive)
        precondition(!login.startHerding(animal:9,destination:destination),"Do not replace an active action")
        cursor(location:0)
        precondition(message.contains("waiting to send") && !login.targeting)
        cursor(location:1) // The legacy server reuses the cursor identifier.
        precondition(message.contains("Destination sent") && !login.targeting)
        speech("The animal walks where it was instructed to.",ordinary:true)
        precondition(message.contains("Destination sent"),"Ordinary speech is not acceptance")
        speech("The animal walks where it was instructed to.")
        precondition(message.contains("Waiting for it to arrive") && login.herdingActive)
        animal(x:10,y:11,z:1); login.tickMovement()
        precondition(login.herdingActive,"Wrong elevation cannot prove arrival")
        animal(x:10,y:11); login.tickMovement()
        precondition(!login.harvestingSessionActive && message.contains("reached its destination"))
        cursor(location:1); precondition(!login.targeting,"Late automatic cursor must not become a manual target")
        now += 10.1; animal(); start(); cursor(location:0)
        speech("That is not a herdable animal.")
        precondition(!login.herdingActive && message.contains("refused"),"Refusal before destination must end the attempt")
        now += 10.1; start(); login.stopHarvest(); cursor(location:0)
        precondition(!login.herdingActive && !login.targeting)
        now += 10.1; start(); login.useSkill(21)
        precondition(!login.harvestingSessionActive,"Manual skills interrupt herding")
        now += 10.1; start(); now += 10.1; login.tickMovement()
        precondition(!login.harvestingSessionActive && message.contains("timed out"))
        now += 10.1; start(); send(Data([0x1D,0,0,0,9])); login.tickMovement()
        precondition(!login.harvestingSessionActive,"Animal leaving the stream stops the action")
        now += 10.1; animal(x:40)
        precondition(!login.startHerding(animal:9,destination:destination) && message.contains("out of reach"))
        animal(); send(Data([0x1D,0x40,0,0,3]))
        send(Data([0x24,0x40,0,0,2,0,0x3C]));send(Data([0x3C,0,5,0,0]))
        send(Data([0x25,0x40,0,0,3,0x0E,0x81,0,0,1,0,0,0,0,0x40,0,0,2,0,0]))
        start();precondition(message.contains("Equipping") && login.harvestActive)
        send(Data([0x2E,0x40,0,0,3,0x0E,0x81,0,2,0,0,0,1,0,0]))
        precondition(login.herdingActive && message.contains("waiting to select"))
        transport.onEvent?(.disconnected)
        precondition(!login.harvestingSessionActive,"Disconnect clears herding and any pending equip")

        let panel=HerdPanel(assets:assets,position:destination)
        var started:UInt32?,point:WalkPoint?,stopped=false
        panel.onRefresh={ [.init(serial:9,body:0xD9,x:11,y:10,z:0)] }
        panel.onStart={started=$0;point=$1};panel.onStop={stopped=true}
        panel.refreshAnimals();panel.startHerding()
        precondition(started==9 && point==destination)
        started=nil;panel.x.stringValue="-1";panel.startHerding();precondition(started==nil)
        panel.setDestination(destination);panel.isWorking={true};panel.startHerding();precondition(started==nil)
        panel.isWorking={false};panel.showResult("The selected animal is no longer visible. Move closer, refresh the list, and choose a new animal before starting again.")
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:400),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=panel;ClassicNativeFont.apply(to:panel);panel.layoutSubtreeIfNeeded()
        precondition(panel.x.font?.fontName=="UltimaXB-ClassicBitmap")
        precondition(panel.x.nextKeyView === panel.y && panel.y.nextKeyView === panel.z)
        precondition(panel.x.textColor == .black && panel.y.textColor == .black && panel.z.textColor == .black)
        for editing in [false,true] {
            if editing { window.makeFirstResponder(panel.x);precondition(panel.x.currentEditor() != nil) }
            let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
            panel.cacheDisplay(in:panel.bounds,to:bitmap)
            let name=editing ? "herding-panel-editing":"herding-panel"
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/\(name).png"))
        }
        panel.closePanel();precondition(stopped)
        print("Herding adapter handles both cursors, refusal, actual arrival, cancellation, ownership, and classic controls")
    }
}
