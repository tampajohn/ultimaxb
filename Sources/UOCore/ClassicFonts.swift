import Foundation

/// Original FONTS.MUL: one header and 224 Latin-1 bitmap glyphs per font.
/// Keep offsets into the file rather than expanding every font into textures.
public struct ClassicFonts {
    public struct Glyph {
        public let sprite: Sprite
        public let offsetY: Int
    }
    private struct Record { let offset:Int, width:Int, height:Int }
    private let bytes: Bytes
    private let fonts: [[Record]]
    public var count: Int { fonts.count }
    public init(data: Data) throws {
        guard data.count <= 16*1024*1024 else { throw AssetError("Font file exceeds size limit") }
        let bytes = Bytes(data)
        var fonts:[[Record]] = [], offset = 0
        while offset < data.count && fonts.count < 10 {
            offset += 1 // font header
            var records:[Record] = []
            for _ in 0..<224 {
                guard offset <= bytes.count-3 else { break }
                let width = try bytes.u8(offset), height = try bytes.u8(offset+1)
                offset += 3
                let size = width*height*2
                guard size <= bytes.count-offset else { break }
                records.append(Record(offset:offset,width:width,height:height)); offset += size
            }
            // Some shipped files have a partial trailing font. Never publish it.
            guard records.count == 224 else { break }
            fonts.append(records)
        }
        guard !fonts.isEmpty else { throw AssetError("No complete classic font") }
        self.bytes = bytes; self.fonts = fonts
    }
    public func glyph(_ scalar: Unicode.Scalar, font:Int = 3) throws -> Glyph? {
        guard fonts.indices.contains(font),(32...255).contains(scalar.value) else { return nil }
        let code = Int(scalar.value), record = fonts[font][code-32]
        var rgba = [UInt8](repeating:0,count:record.width*record.height*4)
        for pixel in 0..<(record.width*record.height) {
            let color = try bytes.u16(record.offset+pixel*2)
            if color != 0 { ArtDecoder.put(color,into:&rgba,at:pixel) }
        }
        let offset:Int
        if code == 0xB8 { offset = 1 }
        else if (0x41...0x5A).contains(code) || (0xC0...0xDF).contains(code) || code == 0xA8 { offset = 0 }
        else if (0x61...0x7A).contains(code) { offset = [2,0,2,2,0,0,2,2,0,0][font] }
        else { offset = [1,0,1,1,-1,0,1,1,0,0][font] }
        return Glyph(sprite:Sprite(width:record.width,height:record.height,rgba:rgba),offsetY:offset)
    }
}
