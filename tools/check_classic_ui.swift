import AppKit
import CoreText
import UOCore
@main struct CheckClassicUI {
    @MainActor static func capture(_ view:NSView,_ name:String) throws {
        let window=NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=view; view.layoutSubtreeIfNeeded()
        ClassicNativeFont.apply(to:view)
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
        ClassicNativeFont.apply(to:login.view)
        precondition(ClassicNativeFont.font?.fontName == "UltimaXB-ClassicBitmap")
        let native=ClassicNativeFont.font!
        let ct=unsafeBitCast(native,to:CTFont.self)
        for code in 32...255 {
            let glyph=try assets.fonts!.glyph(Unicode.Scalar(code)!,font:9)!
            var character=UniChar(code), mapped=CGGlyph(0), advance=CGSize.zero
            precondition(CTFontGetGlyphsForCharacters(ct,&character,&mapped,1))
            CTFontGetAdvancesForGlyphs(ct,.horizontal,&mapped,&advance,1)
            precondition(abs(advance.width-CGFloat(max(1,glyph.sprite.width)))<0.01,"Game glyph advance changed")
        }
        for id in [0x845,0x846,0x1F,0xD8] {
            precondition(ClassicControlArt.image(id) != nil,"Missing classic scroll sprite")
        }
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:150,height:120))
        let document=NSView(frame:NSRect(x:0,y:0,width:400,height:400))
        scroll.documentView=document; scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true
        ClassicNativeFont.apply(to:scroll)
        precondition(scroll.verticalScroller is ClassicScroller && scroll.horizontalScroller is ClassicScroller)
        scroll.contentView.scroll(to:NSPoint(x:30,y:60)); scroll.reflectScrolledClipView(scroll.contentView)
        precondition(scroll.contentView.bounds.origin == NSPoint(x:30,y:60))
        try capture(scroll,"classic-scroll-controls")
        let quantity=StackQuantityPanel(maximum:100,assets:assets)
        let slider=descendants(quantity).compactMap { $0 as? NSSlider }.first!
        precondition(slider.cell is ClassicSliderCell)
        try capture(quantity,"classic-quantity-controls")
        precondition(descendants(quantity).compactMap { $0 as? NSTextField }.filter { $0.isEditable }.allSatisfy { !$0.isBezeled })
        let controls=descendants(login.view)
        let account=controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel()=="Account name" }!
        let password=controls.compactMap { $0 as? NSSecureTextField }.first!
        precondition(account.font?.fontName == "UltimaXB-ClassicBitmap")
        precondition(password.font?.fontName == "UltimaXB-ClassicBitmap")
        let editorWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),styleMask:[.titled],backing:.buffered,defer:false)
        editorWindow.contentView=loginHost
        account.stringValue="Typography fixture"
        editorWindow.makeFirstResponder(account)
        ClassicNativeFont.apply(to:loginHost)
        precondition((account.currentEditor() as? NSTextView)?.font?.fontName == "UltimaXB-ClassicBitmap")
        precondition(account.stringValue == "Typography fixture")
        editorWindow.makeFirstResponder(nil)
        account.stringValue=""
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
        let recovery=descendants(travel).compactMap { $0 as? ClassicButton }.first {
            $0.action == NSSelectorFromString("toggleRecovery:")
        }!
        let previous=travel.dropGatheredWhenOverloaded
        recovery.performClick(nil)
        precondition(travel.dropGatheredWhenOverloaded != previous)
        let reopened=TravelPanel(assets:assets,scope:"ui-check")
        precondition(reopened.dropGatheredWhenOverloaded == travel.dropGatheredWhenOverloaded)
        recovery.performClick(nil)
        try capture(travel,"travel-journal")
        print("Login, sidebar, and travel journal rendered from installed assets; no credentials loaded or network requests sent")
    }
}
