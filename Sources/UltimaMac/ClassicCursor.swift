import AppKit
import UOCore

@MainActor
final class ClassicCursor {
    private let assets: ClientAssets
    private var cache: [Int: NSCursor] = [:]
    init(assets: ClientAssets) { self.assets = assets }
    func cursor(war: Bool = false, targeting: Bool = false, pickup: Bool = false, direction: Int? = nil) -> NSCursor {
        let id = CursorArt.graphic(war: war, targeting: targeting, pickup: pickup, direction: direction)
        if let value = cache[id] { return value }
        guard let sprite = try? assets.sprite(id+0x4000) else { return targeting ? .crosshair : .arrow }
        let art = CursorArt(sprite: sprite)
        guard let provider = CGDataProvider(data: Data(art.sprite.rgba) as CFData),
              let image = CGImage(width: sprite.width, height: sprite.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: sprite.width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return .arrow }
        let cursor = NSCursor(image: NSImage(cgImage: image, size: NSSize(width: sprite.width, height: sprite.height)), hotSpot: NSPoint(x: art.hotX, y: art.hotY))
        cache[id] = cursor
        return cursor
    }
}
