import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        ClassicNativeFont.install(assets.fonts)
        ClassicControlArt.install(assets)
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
        for icons in [true,false] {
            for count in [1,12] {
                var data=Data([0x7C,0,0,0,0,0,1,0,1]+text("Choose a recipe")+[UInt8(count)])
                for i in 1...count {
                    data += Data((icons ? [0x0F,0xBB,0,0]:[0,0,0,0])+text("Recipe \(i)"))
                }
                data[1]=UInt8(data.count>>8);data[2]=UInt8(data.count&255)
                let sample=ServerMenuPanel(menu:try ServerMenu.decode(data),assets:assets)
                host.addSubview(sample); sample.layoutSubtreeIfNeeded()
                let area=sample.subviews.compactMap { $0 as? NSScrollView }.first!
                let document=area.documentView!
                precondition(area.verticalScrollElasticity == .none && area.horizontalScrollElasticity == .none)
                if icons {
                    precondition(document.frame.height == area.contentSize.height,"Icon rows cannot overflow vertically")
                    precondition(document.subviews.allSatisfy { $0.frame.maxY<=document.bounds.height },"Icons must fit above the scrollbar")
                } else {
                    precondition(document.frame.width == area.contentSize.width,"Text menus cannot overflow horizontally")
                }
                let clip=area.contentView
                let proposed=NSRect(x:10000,y:10000,width:clip.bounds.width,height:clip.bounds.height)
                let clamped=clip.constrainBoundsRect(proposed)
                precondition(clamped.minX == max(0,document.frame.width-clip.bounds.width))
                precondition(clamped.minY == max(0,document.frame.height-clip.bounds.height))
                let negative=clip.constrainBoundsRect(NSRect(x:-100,y:-100,width:clip.bounds.width,height:clip.bounds.height))
                precondition(negative.minX==0 && negative.minY==0,"Menus cannot scroll before the first choice")
                sample.removeFromSuperview()
            }
        }
        print("Server menu first paint matches moved paint, uses game fonts and preserves option selection")
    }
}
