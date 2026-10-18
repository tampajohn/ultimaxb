import Foundation

/// Classic 8-entry hue groups: 4-byte group header, then 88 bytes per hue.
/// Color lookup and partial-hue behavior follow ClassicUO HuesLoader.cs;
/// see LICENSES/ClassicUO.txt.
public struct HuePalette {
    let colors: [UInt8]
    let partial: Bool
    public func color(red: UInt8, green: UInt8, blue: UInt8) -> (UInt8, UInt8, UInt8) {
        if partial && (red != green || red != blue) { return (red, green, blue) }
        // Recover the original RGB555 red index from the expanded byte. Round
        // to nearest: truncation would map source levels 1...30 one slot low.
        let index = (Int(red) * 31 + 127) / 255 * 4
        return (colors[index], colors[index + 1], colors[index + 2])
    }
}

struct HueTable {
    let bytes: Bytes
    init(_ data: Data) { bytes = Bytes(data) }
    func palette(_ hue: Int, partial: Bool = false) throws -> HuePalette? {
        // Spectral rendering is separate from palette replacement.
        guard hue & 0x4000 == 0 else { return nil }
        let id = hue & 0x3FFF
        guard id > 0 else { return nil }
        let index = id - 1
        let offset = index / 8 * 708 + 4 + index % 8 * 88
        guard offset + 88 <= bytes.count else { return nil }
        var colors = [UInt8](repeating: 0, count: 32 * 4)
        for i in 0..<32 { ArtDecoder.put(try bytes.u16(offset + i * 2), into: &colors, at: i) }
        return HuePalette(colors: colors, partial: partial || hue & 0x8000 != 0)
    }
}
