import AppKit
import UOCore
@main struct Check {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let panel = CharacterSelectionPanel(assets:assets)
        var data = Data([0x86,0,124,2])
        for name in ["Example Warrior","Example Mage"] { data.append(contentsOf:Array(name.utf8)+Array(repeating:0,count:60-name.utf8.count)) }
        panel.update(try CharacterList.decodeUpdate(data,cities:[]).characters, message:"That character is still logged in or waiting for logout.")
        let window = NSWindow(contentRect:panel.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = panel
        let bitmap = panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
        panel.cacheDisplay(in:panel.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/character-selection.png"))
        var deletions = 0
        panel.onDelete = { _ in deletions += 1 }
        let delete = panel.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Delete Character" }!
        delete.performClick(nil)
        precondition(deletions == 0)
        let cancel = panel.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Cancel" }!
        cancel.performClick(nil); precondition(deletions == 0)
        panel.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Delete Character" }!.performClick(nil)
        panel.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Confirm deletion" }!.performClick(nil)
        precondition(deletions == 1)
        print("Character selection artwork and explicit confirmation checks passed")
        _ = app
    }
}
