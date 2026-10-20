import AppKit
import UOCore

@main struct Check {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        ClassicNativeFont.install(assets.fonts)
        for role in [9,4] {
        for secure in [false,true] {
            for height in [21,30,44] {
                let host=AlignmentHost(frame:NSRect(x:0,y:0,width:220,height:80))
                let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
                window.contentView=host
                let field:NSTextField=secure ? ClassicSecureEntry(frame:.zero) : ClassicEntry(frame:.zero)
                field.frame=NSRect(x:10,y:10,width:180,height:height)
                field.font=ClassicNativeFont.assetFont(role)
                field.stringValue="Agyp09"; field.focusRingType = .none
                field.textColor = .black; field.backgroundColor = .white
                host.addSubview(field); ClassicNativeFont.apply(to:host)
                window.makeFirstResponder(nil)
                func bounds(_ label:String)throws->(Int,Int,CGFloat) {
                    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                    let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
                    host.cacheDisplay(in:host.bounds,to:bitmap)
                    let scale=CGFloat(bitmap.pixelsHigh)/host.bounds.height
                    var rows:[Int]=[]
                    for y in Int(10*scale)..<Int(CGFloat(10+height)*scale) {
                        for x in Int(12*scale)..<Int(160*scale) {
                            let color=bitmap.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                            if color.alphaComponent>0.9 && max(color.redComponent,color.greenComponent,color.blueComponent)<0.25 {
                                rows.append(y); break
                            }
                        }
                    }
                    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/entry-font\(role)-\(secure)-\(height)-\(label).png"))
                    precondition(!rows.isEmpty,"Field glyphs must remain visible")
                    return (rows.min()!,rows.max()!,scale)
                }
                let idle=try bounds("idle")
                window.makeFirstResponder(field)
                guard let editor=field.currentEditor() as? NSTextView else { fatalError("No field editor") }
                ClassicNativeFont.apply(to:host)
                precondition(editor.font?.fontName == ClassicNativeFont.assetFont(role).fontName,"Font enforcement must preserve the editing role")
                precondition(field.font?.fontName == ClassicNativeFont.assetFont(role).fontName)
                editor.setSelectedRange(NSRange(location:editor.string.utf16.count,length:0))
                editor.insertionPointColor = .clear
                let editing=try bounds("editing")
                precondition(idle.0==editing.0 && idle.1==editing.1,"Focusing a field must not move the glyphs: role=\(role), secure=\(secure), height=\(height), idle=\(idle), editing=\(editing), asc=\(field.font!.ascender), desc=\(field.font!.descender), line=\(NSLayoutManager().defaultLineHeight(for:field.font!)), baseline=\(NSLayoutManager().defaultBaselineOffset(for:field.font!)), editor=\(editor.frame), cell=\(field.cell!.drawingRect(forBounds:field.bounds))")
                let center=CGFloat(idle.0+idle.1+1)/2
                let expected=(10+CGFloat(height)/2)*idle.2
                precondition(abs(center-expected)<=1,"Visible game glyphs must be vertically centered: role=\(role), secure=\(secure), height=\(height), ink=\(idle), expected=\(expected)")
                precondition(field.stringValue=="Agyp09")
                window.makeFirstResponder(nil)
            }
        }
        }
        print("Normal and secure game glyphs stay centered before/during editing at all three field heights")
    }
}
@MainActor private final class AlignmentHost:NSView { override var isFlipped:Bool { true } }
