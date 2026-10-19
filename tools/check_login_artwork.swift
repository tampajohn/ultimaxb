import AppKit
import UOCore
@main struct CheckLoginArtwork {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let panel=LoginArtwork(assets:assets)
        for id in [0x3E8,0x410,0x411,0x415,0x418] {
            precondition(panel.image(id) != nil,"Missing classic login asset \(id)")
        }
        let window=NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView=panel
        let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
        panel.cacheDisplay(in:panel.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/classic-login.png"))
        print("Original login assets decoded and composed")
    }
}
