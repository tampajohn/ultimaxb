import AppKit

/// The classic client's small formatting vocabulary, not a web document.
/// Unsupported tags contribute no behavior; no URLs or external resources load.
@MainActor enum GumpText {
    static func attributed(_ source:String, color:NSColor)->NSAttributedString {
        let result = NSMutableAttributedString(string:"")
        var bold = 0, italic = 0, underline = 0, centered = 0
        var colors:[NSColor] = [color]
        func append(_ text:String) {
            var traits:NSFontTraitMask = []
            if bold > 0 { traits.insert(.boldFontMask) }
            if italic > 0 { traits.insert(.italicFontMask) }
            let font = NSFontManager.shared.convert(.systemFont(ofSize:14),toHaveTrait:traits)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = centered > 0 ? .center : .left
            result.append(NSAttributedString(string:entities(text),attributes:[.font:font,.foregroundColor:colors.last ?? color,.paragraphStyle:paragraph,.underlineStyle:underline > 0 ? NSUnderlineStyle.single.rawValue : 0]))
        }
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard let open = source[cursor...].firstIndex(of:"<") else { append(String(source[cursor...])); break }
            append(String(source[cursor..<open]))
            guard let close = source[open...].firstIndex(of:">") else { append(String(source[open...])); break }
            let tag = source[source.index(after:open)..<close].trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            let name = tag.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            switch name {
            case "b", "strong": bold += 1
            case "/b", "/strong": bold = max(0,bold-1)
            case "i", "em": italic += 1
            case "/i", "/em": italic = max(0,italic-1)
            case "u": underline += 1
            case "/u": underline = max(0,underline-1)
            case "center": if result.length > 0 { append("\n") }; centered += 1
            case "/center": append("\n"); centered = max(0,centered-1)
            case "br", "br/", "p", "/p": append("\n")
            case "basefont", "font":
                if let range = tag.range(of:"color\\s*=\\s*[\"']?#?([0-9a-f]{6})",options:.regularExpression) {
                    let value = String(tag[range]).suffix(6)
                    if let rgb = UInt32(value,radix:16) {
                        colors.append(NSColor(srgbRed:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1))
                    }
                }
            case "/basefont", "/font": if colors.count > 1 { colors.removeLast() }
            default: break
            }
            cursor = source.index(after:close)
        }
        return result
    }
    private static func entities(_ source:String)->String {
        var output = "", cursor = source.startIndex
        let named = ["amp":"&","lt":"<","gt":">","quot":"\"","apos":"'","nbsp":"\u{00A0}"]
        while cursor < source.endIndex {
            if source[cursor] == "&", let end = source[cursor...].prefix(14).firstIndex(of:";") {
                let name = String(source[source.index(after:cursor)..<end])
                var decoded = named[name]
                if name.hasPrefix("#") {
                    let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
                    if let value = UInt32(name.dropFirst(hex ? 2 : 1),radix:hex ? 16 : 10),let scalar = UnicodeScalar(value) { decoded = String(scalar) }
                }
                if let decoded { output += decoded; cursor = source.index(after:end); continue }
            }
            output.append(source[cursor]); cursor = source.index(after:cursor)
        }
        return output
    }
}
