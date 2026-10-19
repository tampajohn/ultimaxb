import AppKit
import UOCore
@main struct CheckWorldLayout {
 @MainActor static func main() throws {
    _ = NSApplication.shared
    let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
    let view=WorldView(assets:assets,options:try Options(["--x","2477","--y","411"]))
    let sidebar=PlaySidebar(definitions:assets.skills,assets:assets)
    view.sidebar=sidebar; view.addSubview(sidebar)
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1600,height:962),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.contentView=view
    let chat=ChatPanel(assets:assets); chat.append("Traveler: Welcome to Minoc."); chat.append("You see a blacksmith."); view.addSubview(chat)
    for i in 0..<30 {
        let size=NSSize(width:[1600,1100,1900][i%3],height:962)
        window.setContentSize(size); view.needsLayout=true; view.layoutSubtreeIfNeeded(); view.refresh()
        precondition(view.imageRect.minX == 280 && view.imageRect.maxX == view.bounds.maxX)
        precondition(view.imageRect.height == view.bounds.height-62)
        let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:bitmap)
        if i == 29 { try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/world-layout.png")) }
    }
    print("30 world redraws/resizes completed; world fills available bounds, sidebar stops above debug bar")
 }
}
