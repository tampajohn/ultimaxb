import AppKit
import UOCore
@main struct CheckClassicUI {
    @MainActor static func capture(_ view:NSView,_ name:String) throws {
        let window=NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=view; view.layoutSubtreeIfNeeded()
        let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/\(name).png"))
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let defaults=UserDefaults(suiteName:"com.ultimaxb.ui-check")!
        defaults.removePersistentDomain(forName:"com.ultimaxb.ui-check")
        let login=LoginOverlay(assets:assets,loginDefaults:defaults)
        login.view.frame=NSRect(x:0,y:0,width:800,height:600)
        let loginHost=NSView(frame:login.view.frame)
        login.show(in:loginHost)
        func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
        let controls=descendants(login.view)
        let account=controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel()=="Account name" }!
        let password=controls.compactMap { $0 as? NSSecureTextField }.first!
        precondition(account.nextKeyView === password,"Tab must move from account to password")
        let remember=controls.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel()=="Remember password in Keychain" }!
        precondition(remember.state == .off); remember.performClick(nil); precondition(remember.state == .on)
        remember.performClick(nil); precondition(remember.state == .off)
        try capture(loginHost,"classic-login-controls")
        controls.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("dismissOverlay") }!.performClick(nil)
        try capture(loginHost,"classic-intro")
        controls.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("enterLogin") }!.performClick(nil)
        precondition(!account.isHiddenOrHasHiddenAncestor)

        let sidebar=PlaySidebar(definitions:assets.skills,assets:assets)
        sidebar.frame=NSRect(x:0,y:0,width:280,height:900)
        var status=CharacterStatus(serial:1)
        var packet=Data([0x11,0,66,0,0,0,1])+Data(repeating:0,count:30)
        packet += Data([0,25,0,30,0,1,0, 0,30,0,15,0,16, 0,12,0,15,0,9,0,16, 0,0,1,44, 0,10,0,55])
        try status.apply(packet); sidebar.updateStatus(status)
        try capture(sidebar,"classic-sidebar")
        let travel=TravelPanel(assets:assets,scope:"ui-check")
        try capture(travel,"travel-journal")
        print("Login, sidebar, and travel journal rendered from installed assets; no credentials loaded or network requests sent")
    }
}
