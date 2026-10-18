import AppKit
import UOCore
@main struct Check {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "com.ultimaxb.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("example.invalid",forKey:"server")
        defaults.set("5000",forKey:"port")
        defaults.set("primary-fixture",forKey:"account")
        defaults.set(false,forKey:"rememberPassword")
        let primary = SavedLogin(defaults:defaults)
        let local = SavedLogin(profile:.local,defaults:defaults)
        precondition(local.host == "127.0.0.1" && local.port == "2593" && local.account.isEmpty)
        let original = defaults.dictionaryRepresentation()
        let name = "fixture-\(UUID().uuidString)"
        precondition(local.save(host:"127.0.0.1",port:"2593",account:name,password:"",remember:false) == 0)
        for key in ["server","port","account","rememberPassword"] {
            precondition((defaults.object(forKey:key) as? NSObject) == (original[key] as? NSObject))
        }
        precondition(primary.host == "example.invalid" && primary.account == "primary-fixture")
        precondition(local.account == name && local.password() == nil)
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let overlay = LoginOverlay(assets:assets,loginDefaults:defaults)
        func all(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(all) }
        let views = all(overlay.view)
        let buttons = views.compactMap { $0 as? NSButton }
        let fields = views.compactMap { $0 as? NSTextField }
        buttons.first { $0.title == "Local Test Center" }!.performClick(nil)
        precondition(fields.contains { $0.stringValue == "127.0.0.1" && !$0.isEditable })
        precondition(fields.contains { $0.stringValue == name })
        buttons.first { $0.title == "Saved Server" }!.performClick(nil)
        precondition(fields.contains { $0.stringValue == "example.invalid" && $0.isEditable })
        precondition(fields.contains { $0.stringValue == "primary-fixture" })
        precondition(local.forget() == 0)
        precondition(primary.host == "example.invalid" && primary.account == "primary-fixture")
        print("Local profile save/forget and login profile switching preserve primary settings")
    }
}
