import AppKit
import CoreText
import UOCore

/// A process-local outline font traced from the installed bitmap glyphs. No
/// proprietary font data is shipped or written to disk. Native editors retain
/// selection, secure entry, clipboard and accessibility with game lettering.
@MainActor enum ClassicNativeFont {
    private static var installed:NSFont?
    private static var observer:NSObjectProtocol?
    static func install(_ fonts:ClassicFonts?) {
        guard installed == nil,let fonts,let data=try? makeFont(fonts),
              let provider=CGDataProvider(data:data as CFData),let cg=CGFont(provider) else { return }
        // CTFont and NSFont are toll-free bridged on macOS. Keep this font
        // process-local rather than registering it in the user font database.
        installed=unsafeBitCast(CTFontCreateWithGraphicsFont(cg,16,nil,nil),to:NSFont.self)
        guard installed != nil else { return }
        observer=NotificationCenter.default.addObserver(forName:NSWindow.didUpdateNotification,object:nil,queue:.main) { _ in
            MainActor.assumeIsolated {
                for window in NSApplication.shared.windows { if let content=window.contentView { apply(to:content) } }
            }
        }
    }
    static var font:NSFont? { installed }
    // Asset-load failure only; installed fonts always take precedence.
    static var uiFont:NSFont { installed ?? NSFont.systemFont(ofSize:16) }
    static func apply(to view:NSView) {
        guard let font=installed else { return }
        if let field=view as? NSTextField,field is ClassicEntry || field is ClassicSecureEntry {
            if field.isBezeled { field.isBezeled=false }
            if field.isBordered { field.isBordered=false }
        }
        if let scroll=view as? NSScrollView { ClassicControlArt.apply(to:scroll) }
        if let control=view as? NSControl,control.font?.fontName != font.fontName { control.font=font }
        if let popup=view as? NSPopUpButton,popup.menu?.font?.fontName != font.fontName { popup.menu?.font=font }
        if let text=view as? NSTextView,(text.isFieldEditor || !text.isRichText),text.font?.fontName != font.fontName { text.font=font }
        for child in view.subviews { apply(to:child) }
    }
    private static func makeFont(_ fonts:ClassicFonts)throws->Data {
        func words(_ values:[Int])->Data { var d=Data(); for v in values { let n=UInt16(truncatingIfNeeded:v); d.append(UInt8(n>>8)); d.append(UInt8(n&255)) }; return d }
        func longs(_ values:[Int])->Data { var d=Data(); for v in values { let n=UInt32(truncatingIfNeeded:v); d.append(contentsOf:[UInt8(n>>24),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)]) }; return d }
        func checksum(_ data:Data)->UInt32 {
            var bytes=Array(data); while bytes.count%4 != 0 { bytes.append(0) }
            var sum:UInt32=0
            for i in stride(from:0,to:bytes.count,by:4) { sum &+= UInt32(bytes[i])<<24 | UInt32(bytes[i+1])<<16 | UInt32(bytes[i+2])<<8 | UInt32(bytes[i+3]) }
            return sum
        }
        let count=225 // .notdef plus Latin-1 32...255
        var glyf=Data(),loca=Data(),metrics=Data()
        var maxPoints=0,maxContours=0,maxAdvance=0
        for index in 0..<count {
            loca.append(longs([glyf.count]))
            var points:[(Int,Int)]=[], ends:[Int]=[]
            var advance=4*64
            if index>0,let scalar=Unicode.Scalar(index+31),let glyph=try? fonts.glyph(scalar,font:min(9,fonts.count-1)) {
                let s=glyph.sprite; advance=max(1,s.width)*64
                for y in 0..<s.height {
                    var x=0
                    while x<s.width {
                        if s.rgba[(y*s.width+x)*4+3]==0 { x += 1; continue }
                        let start=x
                        while x<s.width && s.rgba[(y*s.width+x)*4+3] != 0 { x += 1 }
                        let top=(14-glyph.offsetY-y)*64, bottom=top-64
                        points += [(start*64,bottom),(start*64,top),(x*64,top),(x*64,bottom)]
                        ends.append(points.count-1)
                    }
                }
            }
            maxPoints=max(maxPoints,points.count); maxContours=max(maxContours,ends.count); maxAdvance=max(maxAdvance,advance)
            metrics.append(words([advance,0]))
            if !points.isEmpty {
                glyf.append(words([ends.count,points.map{$0.0}.min()!,points.map{$0.1}.min()!,points.map{$0.0}.max()!,points.map{$0.1}.max()!]))
                glyf.append(words(ends)); glyf.append(words([0])) // no hinting instructions
                glyf.append(Data(repeating:1,count:points.count)) // on-curve, signed word deltas
                var previous=0
                for p in points { glyf.append(words([p.0-previous])); previous=p.0 }
                previous=0
                for p in points { glyf.append(words([p.1-previous])); previous=p.1 }
                while glyf.count%4 != 0 { glyf.append(0) }
            }
        }
        loca.append(longs([glyf.count]))
        var head=longs([0x10000,0x10000,0,0x5F0F3CF5])+words([3,1024])
        head.append(Data(repeating:0,count:16)); head.append(words([0,-1024,maxAdvance,2048,0,8,2,1,0]))
        let hhea=longs([0x10000])+words([896,-256,0,maxAdvance,0,0,maxAdvance,1,0,0,0,0,0,0,0,count])
        let maxp=longs([0x10000])+words([count,maxPoints,maxContours,0,0,1,0,0,0,0,0,0,0,0])
        // Format 4: direct sequential mapping for Latin-1 plus sentinel.
        let cmapSub=words([4,32,0,4,4,1,0,255,65535,0,32,65535,-31,1,0,0])
        let cmap=words([0,1,3,1])+longs([12])+cmapSub
        var nameRecords=Data(),nameStrings=Data()
        for (id,value) in [(1,"UltimaXB Classic Bitmap"),(2,"Regular"),(4,"UltimaXB Classic Bitmap"),(6,"UltimaXB-ClassicBitmap")] {
            let string=words(value.utf16.map(Int.init))
            nameRecords.append(words([3,1,0x409,id,string.count,nameStrings.count])); nameStrings.append(string)
        }
        let name=words([0,4,54])+nameRecords+nameStrings
        let post=longs([0x30000,0])+words([0,0])+longs([0,0,0,0,0])
        let tables:[(String,Data)]=[("cmap",cmap),("glyf",glyf),("head",head),("hhea",hhea),("hmtx",metrics),("loca",loca),("maxp",maxp),("name",name),("post",post)]
        var output=longs([0x10000])+words([9,128,3,16]),body=Data(),headOffset=0
        for (tag,data) in tables {
            let offset=12+tables.count*16+body.count
            if tag=="head" { headOffset=offset }
            output.append(Data(tag.utf8)); output.append(longs([Int(checksum(data)),offset,data.count]))
            body.append(data); while body.count%4 != 0 { body.append(0) }
        }
        output.append(body)
        output.replaceSubrange(headOffset+8..<headOffset+12,with:longs([Int(0xB1B0AFBA &- checksum(output))]))
        return output
    }
}
