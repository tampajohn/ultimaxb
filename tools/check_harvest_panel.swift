import AppKit
import UOCore

@MainActor private final class WorldInputProbe:NSResponder {
    var received=0
    override func mouseDown(with event:NSEvent) { received += 1 }
    override func mouseDragged(with event:NSEvent) { received += 1 }
    override func mouseUp(with event:NSEvent) { received += 1 }
    override func rightMouseDown(with event:NSEvent) { received += 1 }
    override func rightMouseDragged(with event:NSEvent) { received += 1 }
    override func rightMouseUp(with event:NSEvent) { received += 1 }
    override func scrollWheel(with event:NSEvent) { received += 1 }
}
@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let suite="com.ultimaxb.harvest-preview.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let position=WalkPoint(x:2584,y:482,z:0)
        let panel=HarvestPanel(assets:assets,scope:"fixture:1",position:position,defaults:defaults)
        let worldInput=WorldInputProbe()
        let click=NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        let overlays:[ClassicPanel]=[panel,ClassicPanel(assets:assets),
            SkillsPanel(definitions:assets.skills,assets:assets),
            PlaySidebar(definitions:assets.skills,assets:assets),
            TravelPanel(assets:assets,scope:"pointer-fixture")]
        for overlay in overlays {
            overlay.nextResponder=worldInput
            overlay.mouseDown(with:click);overlay.mouseDragged(with:click);overlay.mouseUp(with:click)
            overlay.rightMouseDown(with:click);overlay.rightMouseDragged(with:click);overlay.rightMouseUp(with:click)
            overlay.scrollWheel(with:click)
            precondition(worldInput.received==0,"Panel backgrounds must not route movement, pickup or scrolling gestures to the world")
            overlay.nextResponder=nil
        }
        var previews=0,clears=0
        panel.onClear={clears += 1}
        panel.onPreview={zone,kind in
            previews += 1
            precondition(zone.minX==2576 && zone.maxX==2592 && kind == .mining)
        }
        panel.preview(); precondition(previews==1)
        panel.radius.stringValue="9223372036854775807"; panel.preview(); precondition(previews==1)
        panel.radius.stringValue="0"; panel.preview(); precondition(previews==1)
        panel.radius.stringValue="8"; panel.x.stringValue="1"; panel.preview(); precondition(previews==1)
        panel.picked(x:2584,y:482); panel.selectWood()
        panel.onPreview={_,kind in precondition(kind == .lumberjacking); previews += 1}
        panel.preview(); precondition(previews==2 && clears>=6)
        let restored=HarvestPanel(assets:assets,scope:"fixture:1",position:.init(x:10,y:10,z:0),defaults:defaults)
        precondition(restored.x.stringValue=="2584" && restored.kind == .lumberjacking)
        let other=HarvestPanel(assets:assets,scope:"fixture:2",position:.init(x:10,y:10,z:0),defaults:defaults)
        precondition(other.x.stringValue=="10" && other.kind == .mining)
        panel.onPlayerPosition={ .init(x:2600,y:490,z:0) }
        panel.centerOnMe()
        precondition(panel.x.stringValue=="2600" && panel.y.stringValue=="490" && panel.radius.stringValue=="8")
        var started=false,stopped=false
        panel.onStart={zone,_ in started=zone.minX==2592 && zone.maxX==2608 }
        panel.onStop={stopped=true}
        panel.startHarvesting(); precondition(started)
        stopped=false; started=false
        let beforeRepeat=previews
        panel.isHarvesting={true}
        panel.startHarvesting()
        precondition(!stopped && !started && previews==beforeRepeat,"Repeated Start must not preview/cancel an active workflow")
        var smelted=false; panel.onSmelt={smelted=true}
        panel.smeltOre(); precondition(!smelted,"Smelting must not interrupt an active run")
        panel.isHarvesting={false}; panel.smeltOre(); precondition(smelted)
        var paused=false; panel.onPauseResume={paused=true}; panel.pauseResume(); precondition(paused)
        panel.stopHarvesting(); precondition(stopped)
        panel.showResult("23 reachable work sites. Gold lines mark the zone; dots mark targets. Start runs up to 100 successes; Stop cancels.")
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:642),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=panel; ClassicNativeFont.apply(to:panel); panel.layoutSubtreeIfNeeded()
        precondition(panel.x.font?.fontName == "UltimaXB-ClassicBitmap")
        precondition(panel.x.nextKeyView === panel.y && panel.y.nextKeyView === panel.radius)
        window.makeFirstResponder(panel.radius)
        precondition(panel.radius.currentEditor() != nil)
        let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds)!
        panel.cacheDisplay(in:panel.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/harvest-panel.png"))
        let before=clears; panel.closePanel(); precondition(clears==before+1 && panel.superview==nil)
        print("Harvest preview validates bounds, isolates saved zones, uses game fonts and clears on close")
    }
}
