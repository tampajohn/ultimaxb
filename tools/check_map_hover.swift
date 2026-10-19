import AppKit
import UOCore
@main struct CheckMapHover {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let host=NSView(frame:NSRect(x:0,y:0,width:280,height:280))
        let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=host
        let panel=MapPanel(assets:assets); panel.frame.origin = .zero; host.addSubview(panel)
        let player=WorldMobile(serial:1,body:400,x:2450,y:430,z:15)
        let enemy=WorldMobile(serial:2,body:400,x:2460,y:430,z:15,notoriety:5)
        panel.update(player:player,mobiles:[player,enemy])
        let location=panel.convert(NSPoint(x:150,y:150),to:nil)
        let event=NSEvent.mouseEvent(with:.mouseMoved,location:location,modifierFlags:[],timestamp:0,
            windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0)!
        panel.mouseMoved(with:event)
        panel.receiveName(SpeechMessage(serial:2,type:6,name:"",text:"Test enemy"))
        precondition(panel.toolTip == "Test enemy")
        let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
        panel.cacheDisplay(in:panel.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/map-feedback.png"))
        panel.update(player:nil,mobiles:[])
        host.addSubview(panel); panel.update(player:player,mobiles:[player,enemy]); panel.mouseMoved(with:event)
        precondition(panel.toolTip == nil,"Names must not survive reconnect with reused serials")
        print("Map hover name delivery and session reset passed; no network traffic")
    }
}
