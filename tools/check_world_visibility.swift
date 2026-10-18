import AppKit
import UOCore

/// Compile with the declarations from UltimaMac/main.swift (without its launch block).
@main struct CheckWorldVisibility {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let view = WorldView(assets: assets, options: try Options(["--land-only"]))
        precondition(!view.rendersStatics, "Offline land-only preview remains available")
        view.player = WorldMobile(serial: 1, body: 400, x: 2493, y: 482, z: 15)
        precondition(view.rendersStatics, "Joining a game must restore scenery even after a land-only preview")
        view.debugCamera = true
        precondition(!view.rendersStatics, "Explicit debug mode retains the preview toggle")
        view.debugCamera = false
        let player = view.player!
        let visibility = try WorldVisibility.around(player: player, assets: assets)
        precondition(visibility.ceiling == nil)
        let full = try WorldRenderer.render(assets, x: player.x, y: player.y,
            statics: view.rendersStatics, visibility: visibility, mobiles: [player])
        let bare = try WorldRenderer.render(assets, x: player.x, y: player.y, statics: false)
        precondition(full.staticCount > 0 && bare.staticCount == 0 && full.rgba != bare.rgba)
        precondition(full.missingCount == 0)
        print("Preview-to-game scenery restored: \(full.staticCount) statics, no missing art, no outdoor ceiling")
    }
}
