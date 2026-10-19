import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        ClassicNativeFont.install(assets.fonts)
        func text(_ s:String)->[UInt8] { [UInt8(s.utf8.count)]+Array(s.utf8) }
        var packet=Data([0x7C,0,0,0,0,0,1,0,1]+text("What would you like to do?")+[1,0x0F,0xBB,0,0]+text("Smithing"))
        packet[1]=UInt8(packet.count>>8); packet[2]=UInt8(packet.count&255)
        let menu=try ServerMenu.decode(packet)
        let panel=ServerMenuPanel(menu:menu,assets:assets)
        let host=NSView(frame:NSRect(x:0,y:0,width:700,height:450))
        let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=host; host.addSubview(panel)
        panel.layoutSubtreeIfNeeded()
        precondition(panel.wantsLayer && panel.layer?.masksToBounds == true)
        let scroll=panel.subviews.compactMap { $0 as? NSScrollView }.first!
        let buttons=scroll.documentView!.subviews.compactMap { $0 as? NSButton }
        precondition(buttons.count==1 && buttons[0].image != nil && buttons[0].imagePosition == .imageOnly)
        precondition(panel.subviews.compactMap { $0 as? NSTextField }.allSatisfy { $0.font?.fontName == ClassicNativeFont.uiFont.fontName })
        func capture()->Data {
            let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
            panel.cacheDisplay(in:panel.bounds,to:bitmap)
            return bitmap.representation(using:.png,properties:[:])!
        }
        let first=capture()
        try first.write(to:URL(fileURLWithPath:"build/server-menu-first.png"))
        panel.frame.origin.x += 30; panel.frame.origin.y += 20
        panel.layoutSubtreeIfNeeded()
        precondition(capture()==first,"Menu must render identically before and after movement")
        var choice:Int?
        panel.onChoose={choice=$0}
        buttons[0].performClick(nil)
        precondition(choice==1)
        print("Server menu first paint matches moved paint, uses game fonts and preserves option selection")
    }
}
