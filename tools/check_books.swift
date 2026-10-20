import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let header=Data([0x93,0x40,0,0,1,1,0,3])+Data("A journal".utf8)+Data(repeating:0,count:51)+Data("Writer".utf8)+Data(repeating:0,count:24)
        var book=try ClassicBook.decodeHeader(header)
        let page=Data([0x66,0,19,0x40,0,0,1,0,1,0,1,0,2,65,0,66,67,68,0])
        let display=BookPanel(book:book,assets:assets)
        let window=NSWindow(contentRect:display.frame,styleMask:[.borderless],backing:.buffered,defer:false); window.contentView=display
        var requests:[Int]=[],saved:[Int:[String]]=[:],saveCount=0,closed=false
        display.onRequest={requests.append($0)}
        display.onSave={_,_,pages in saved=pages; saveCount += 1}
        display.onClose={closed=true}
        display.showPages(); display.showPages(); precondition(requests == [1])
        try book.receivePages(page); display.update(book)
        let scrolls=display.subviews.compactMap {$0 as? NSScrollView}
        let editor=scrolls[1].documentView as! NSTextView
        precondition(editor.isEditable && editor.string == "A\nBCD")
        editor.string="A new story"
        display.update(book)
        precondition(editor.string == "A new story","Late responses must not overwrite the draft")
        precondition(display.save() && saveCount == 1 && saved[1] != nil)
        precondition(display.message.contains("confirmation unavailable"))
        display.turn(1); precondition(display.page == 2 && requests == [1,2,3])
        display.turn(1); precondition(display.page == 2)
        display.turn(-1); precondition(display.page == 0)
        let title=display.subviews.compactMap {$0 as? ClassicEntry}.first!
        title.stringValue=String(repeating:"Long title ",count:8)
        precondition(!display.save() && saveCount == 1 && !title.stringValue.isEmpty)
        func capture(_ name:String) throws {
            display.displayIfNeeded()
            let image=display.bitmapImageRepForCachingDisplay(in:display.bounds)!
            display.cacheDisplay(in:display.bounds,to:image)
            try image.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/\(name).png"))
        }
        try capture("ordinary-book")
        window.makeFirstResponder(title); title.selectText(nil)
        try capture("ordinary-book-editing")
        precondition(title.font?.fontName == ClassicNativeFont.uiFont.fontName)
        title.stringValue="Short title"
        precondition(display.save())
        let right=NSEvent.mouseEvent(with:.rightMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        display.rightMouseDown(with:right); precondition(closed)
        let requestCount=requests.count
        display.update(try ClassicBook.decodeHeader(header))
        precondition(requests.count == requestCount+1 && requests.last == 1)
        var readOnlyHeader=header; readOnlyHeader[5]=0
        var readOnly=try ClassicBook.decodeHeader(readOnlyHeader); try readOnly.receivePages(page)
        display.update(readOnly)
        precondition(!editor.isEditable && !title.isEditable && title.stringValue == readOnly.title)

        let suite="com.ultimaxb.books.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(false,forKey:"rememberPassword")
        let connection=GameConnection(),login=LoginOverlay(assets:assets,loginDefaults:defaults,connection:connection)
        var seen:ClassicBook?,removed=0
        login.onBook={_,book in if book == nil {removed += 1}; seen=book}
        var entry=Data(repeating:0,count:37); entry[0]=0x1B; entry[4]=1
        entry.replaceSubrange(9..<18,with:[1,0x90,0,10,0,10,0,0,2])
        connection.onEvent?(.gameData(entry+Data([0x55])+header+page))
        precondition(seen?.pages[1] == ["A","BCD"])
        try login.saveBook(0x40000001,title:"Saved",author:"Writer",pages:[1:["Text"]])
        login.closeBook(0x40000001); precondition(removed == 1)
        connection.onEvent?(.gameData(page)); precondition(seen == nil)
        do { try login.saveBook(0x40000001,title:"no",author:"",pages:[:]); preconditionFailure("closed book accepted") } catch {}
        connection.onEvent?(.gameData(header)); connection.onEvent?(.disconnected)
        precondition(seen == nil && removed == 2)
        print("Ordinary books load pages, preserve drafts, validate edits, use game artwork/fonts and clear on close/disconnect")
    }
}
