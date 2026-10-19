import AppKit

/// Use the same content rectangle for display and the native field editor.
/// Center the visible game glyphs, whose bitmap ink occupies only part of the
/// font's line box, rather than centering that line box alone.
@MainActor private func centeredEntryRect(_ bounds:NSRect,font:NSFont?,view:NSView)->NSRect {
    guard let font else { return bounds }
    let line=ceil(font.ascender-font.descender+font.leading)
    let text="Ag" as NSString
    let ink=text.boundingRect(with:NSSize(width:1000,height:1000),options:[.usesDeviceMetrics],attributes:[.font:font])
    let optical=max(0,(line-ink.height)/2)
    let shift=max(0,(bounds.height-line)/2)+optical
    return NSRect(x:bounds.minX,y:bounds.minY+(view.isFlipped ? shift : -shift),width:bounds.width,height:line)
}
@MainActor final class ClassicEntryCell:NSTextFieldCell {
    override func draw(withFrame rect:NSRect,in view:NSView) {
        let background=drawsBackground
        if background { backgroundColor?.setFill(); rect.fill(); drawsBackground=false }
        super.draw(withFrame:rect,in:view)
        if background { drawsBackground=true }
    }
    override func drawingRect(forBounds rect:NSRect)->NSRect {
        guard let view=controlView else { return super.drawingRect(forBounds:rect) }
        return centeredEntryRect(super.drawingRect(forBounds:rect),font:font,view:view)
    }
    override func select(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,start:Int,length:Int) {
        super.select(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,start:start,length:length)
    }
    override func edit(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,event:NSEvent?) {
        super.edit(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,event:event)
    }
}
@MainActor final class ClassicSecureEntryCell:NSSecureTextFieldCell {
    override func draw(withFrame rect:NSRect,in view:NSView) {
        let background=drawsBackground
        if background { backgroundColor?.setFill(); rect.fill(); drawsBackground=false }
        super.draw(withFrame:rect,in:view)
        if background { drawsBackground=true }
    }
    override func drawingRect(forBounds rect:NSRect)->NSRect {
        guard let view=controlView else { return super.drawingRect(forBounds:rect) }
        return centeredEntryRect(super.drawingRect(forBounds:rect),font:font,view:view)
    }
    override func select(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,start:Int,length:Int) {
        super.select(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,start:start,length:length)
    }
    override func edit(withFrame rect:NSRect,in view:NSView,editor:NSText,delegate:Any?,event:NSEvent?) {
        super.edit(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,event:event)
    }
}
@MainActor final class ClassicEntry:NSTextField {
    override init(frame:NSRect) {
        super.init(frame:frame)
        isBezeled=false; isBordered=false; drawsBackground=true
        backgroundColor=NSColor(calibratedRed:0.76,green:0.71,blue:0.57,alpha:1)
        textColor = .black; font=ClassicNativeFont.uiFont
    }
    required init?(coder:NSCoder) { super.init(coder:coder) }
    override class var cellClass:AnyClass? { get { ClassicEntryCell.self } set {} }
}
@MainActor final class ClassicSecureEntry:NSSecureTextField {
    override init(frame:NSRect) {
        super.init(frame:frame)
        isBezeled=false; isBordered=false; drawsBackground=true
        backgroundColor=NSColor(calibratedRed:0.76,green:0.71,blue:0.57,alpha:1)
        textColor = .black; font=ClassicNativeFont.uiFont
    }
    required init?(coder:NSCoder) { super.init(coder:coder) }
    override class var cellClass:AnyClass? { get { ClassicSecureEntryCell.self } set {} }
}
