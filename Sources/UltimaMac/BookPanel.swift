import AppKit
import UOCore

@MainActor final class BookPanel:NSView {
    private(set) var book:ClassicBook
    private let art:LoginArtwork
    private let text:ClassicText
    private let fonts:ClassicFonts?
    private let titleField=ClassicEntry(frame:.zero), authorField=ClassicEntry(frame:.zero)
    private var editors:[NSTextView]=[], scrolls:[NSScrollView]=[]
    private var drafts:[Int:String]=[:], requested:Set<Int>=[]
    private(set) var page=0
    private var drag:NSPoint?
    var onRequest:((Int)->Void)?
    var onSave:((String,String,[Int:[String]]) throws -> Void)?
    var onClose:(()->Void)?
    private(set) var message=""
    override var isFlipped:Bool { true }
    init(book:ClassicBook,assets:ClientAssets) {
        self.book=book; fonts=assets.fonts; art=LoginArtwork(assets:assets); text=ClassicText(assets.fonts,color:(45,30,15),outlined:false)
        super.init(frame:NSRect(x:310,y:70,width:420,height:310))
        ClassicNativeFont.install(assets.fonts); ClassicControlArt.install(assets)
        for (field,rect,label) in [(titleField,NSRect(x:41,y:65,width:150,height:32),"Book title"),(authorField,NSRect(x:41,y:160,width:150,height:24),"Book author")] {
            field.frame=rect; field.drawsBackground=false; field.isEditable=book.writable
            field.setAccessibilityLabel(label); addSubview(field)
        }
        for x in [38,224] {
            let scroll=NSScrollView(frame:NSRect(x:x,y:34,width:158,height:166))
            scroll.drawsBackground=false; scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true
            ClassicControlArt.apply(to:scroll)
            let editor=NSTextView(frame:NSRect(x:0,y:0,width:142,height:166))
            editor.isRichText=false; editor.font=ClassicNativeFont.uiFont; editor.textColor=NSColor(calibratedRed:0.18,green:0.12,blue:0.06,alpha:1)
            editor.drawsBackground=false; editor.isVerticallyResizable=true; editor.isHorizontallyResizable=false
            editor.textContainer?.widthTracksTextView=true; editor.textContainerInset = .zero
            editor.minSize=NSSize(width:0,height:166); editor.maxSize=NSSize(width:142,height:CGFloat.greatestFiniteMagnitude)
            scroll.documentView=editor; addSubview(scroll); editors.append(editor); scrolls.append(scroll)
        }
        let save=ClassicButton("Save",fonts:assets.fonts,target:self,action:#selector(savePressed))
        save.frame=NSRect(x:160,y:250,width:100,height:25); save.isHidden = !book.writable; addSubview(save)
        let reload=ClassicButton("Reload page",fonts:assets.fonts,target:self,action:#selector(reloadPressed))
        reload.frame=NSRect(x:270,y:250,width:145,height:25); addSubview(reload)
        titleField.stringValue=book.title; authorField.stringValue=book.author
        showPages()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func capture() {
        for side in 0..<2 {
            let p=page+side
            if p>0, p<=book.pageCount,book.pages[p] != nil,book.writable {
                if editors[side].string != book.pages[p]?.joined(separator:"\n") { drafts[p]=editors[side].string }
                else { drafts.removeValue(forKey:p) }
            }
        }
    }
    func update(_ value:ClassicBook) {
        capture()
        if value.pages.isEmpty && !book.pages.isEmpty { requested.removeAll() }
        if !value.writable || titleField.stringValue == book.title { titleField.stringValue=value.title }
        if !value.writable || authorField.stringValue == book.author { authorField.stringValue=value.author }
        book=value
        if !book.writable { drafts.removeAll() }
        showPages()
    }
    func showPages() {
        titleField.isHidden=page != 0; authorField.isHidden=page != 0
        titleField.isEditable=book.writable; authorField.isEditable=book.writable
        for side in 0..<2 {
            let p=page+side,visible=p>0 && p<=book.pageCount
            scrolls[side].isHidden = !visible
            editors[side].isEditable=visible && book.writable && book.pages[p] != nil
            editors[side].setAccessibilityLabel("Book page \(p)")
            editors[side].string=drafts[p] ?? book.pages[p]?.joined(separator:"\n") ?? "Loading page..."
            if visible,book.pages[p] == nil,!requested.contains(p),onRequest != nil { requested.insert(p); onRequest?(p) }
        }
        needsDisplay=true
    }
    func turn(_ delta:Int) {
        capture(); page=max(0,min((book.pageCount/2)*2,page+delta*2)); showPages()
    }
    @objc private func reloadPressed() {
        // Keep local drafts intact; a late response must not erase unsaved writing.
        for p in page...page+1 where p>0 && p<=book.pageCount { onRequest?(p) }
    }
    @discardableResult func save() -> Bool {
        guard book.writable else { return true }
        window?.makeFirstResponder(self); capture()
        do {
            var changed:[Int:[String]] = [:]
            for (p,draft) in drafts where draft != book.pages[p]?.joined(separator:"\n") {
                var lines:[String]=[]
                for paragraph in draft.components(separatedBy:"\n") {
                    var line=""
                    for character in paragraph {
                        if !line.isEmpty && text.size(line+String(character)).width>135 { lines.append(line); line="" }
                        line.append(character)
                    }
                    lines.append(line)
                }
                _ = try book.writePage(p,lines:lines); changed[p]=lines
            }
            _ = try book.writeHeader(title:titleField.stringValue,author:authorField.stringValue)
            guard let onSave else { throw AssetError("Book is no longer connected.") }
            if !changed.isEmpty || titleField.stringValue != book.title || authorField.stringValue != book.author {
                try onSave(titleField.stringValue,authorField.stringValue,changed)
                book.title=titleField.stringValue; book.author=authorField.stringValue
                book.pages.merge(changed,uniquingKeysWith:{_,new in new}); drafts.removeAll()
                message="Edits sent; server confirmation unavailable."
            }
            showPages(); return true
        } catch { message=String(describing:error); needsDisplay=true; return false }
    }
    @objc private func savePressed() { _=save() }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        art.drawImage(0x1FE,at:.zero)
        if page>0 { art.drawImage(0x1FF,at:.zero) }
        if page+2<=book.pageCount { art.drawImage(0x200,at:NSPoint(x:356,y:0)) }
        if page==0 { text.draw("Title",at:NSPoint(x:78,y:32)); text.draw("by",at:NSPoint(x:88,y:134)) }
        for side in 0..<2 where page+side>0 && page+side<=book.pageCount { text.draw(String(page+side),at:NSPoint(x:side==0 ? 112:299,y:202)) }
        if !message.isEmpty {
            NSColor(calibratedRed:0.15,green:0.13,blue:0.09,alpha:1).setFill(); NSRect(x:0,y:277,width:420,height:33).fill()
            let label=ClassicText(fonts,color:(230,215,170))
            for (i,line) in label.lines(message,width:410).prefix(2).enumerated() { label.draw(line,at:NSPoint(x:5,y:278+i*16)) }
        }
    }
    override func mouseDown(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        if p.y<36 && p.x<64 && page>0 { turn(-1); return }
        if p.y<36 && p.x>=356 && page+2<=book.pageCount { turn(1); return }
        drag=event.locationInWindow
    }
    override func mouseDragged(with event:NSEvent) {
        guard let drag,let parent=superview else { return }
        let a=parent.convert(drag,from:nil),b=parent.convert(event.locationInWindow,from:nil)
        frame.origin.x += b.x-a.x; frame.origin.y += b.y-a.y; self.drag=event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { drag=nil }
    override func rightMouseDown(with event:NSEvent) { if save() { onClose?() } }
    override func scrollWheel(with event:NSEvent) {}
}
