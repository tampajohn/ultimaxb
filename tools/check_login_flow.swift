import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "com.ultimaxb.flow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(false,forKey:"rememberPassword")
        defaults.set("fixture",forKey:"account")
        let transport=GameConnection()
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let overlay=LoginOverlay(assets:assets,loginDefaults:defaults,connection:transport)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:800),styleMask:[.titled],backing:.buffered,defer:false)
        overlay.show(in:window.contentView!)
        func all(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(all) }
        func click(_ selector:String) {
            let button=all(overlay.view).compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString(selector) && !$0.isHiddenOrHasHiddenAncestor }!
            button.performClick(nil)
        }
        func accountVisible()->Bool {
            all(overlay.view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "fixture" && !$0.isHiddenOrHasHiddenAncestor }
        }
        precondition(accountVisible())
        var packet=Data([0xA8,0,46,0,0,1,0,0])
        packet.append(contentsOf:Array("Test shard".utf8)+Array(repeating:0,count:22))
        packet.append(contentsOf:[0,0,127,0,0,1])
        guard case .servers(_,let entries)=try LoginResponse.decode(packet) else { fatalError() }
        transport.onEvent?(.servers(entries))
        precondition(!accountVisible())
        let select=all(overlay.view).compactMap { $0 as? NSButton }.first { $0.title == "Select Server" }!
        precondition(select.imagePosition == .noImage)
        precondition((select as? ClassicButton)?.gemBackground != nil)
        if let rep=overlay.view.bitmapImageRepForCachingDisplay(in:overlay.view.bounds) {
            overlay.view.cacheDisplay(in:overlay.view.bounds,to:rep)
            try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/gem-shard-selection.png"))
        }
        click("dismissOverlay")
        click("enterLogin")
        precondition(accountVisible())
        precondition(all(overlay.view).compactMap { $0 as? NSPopUpButton }.allSatisfy { $0.isHiddenOrHasHiddenAncestor })
        transport.onEvent?(.connecting)
        transport.onEvent?(.failed("Fixture failure"))
        precondition(accountVisible())
        print("Offline shard/back/login and connection-failure transitions passed")
    }
}
