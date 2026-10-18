import Foundation
@testable import UOCore

/// Installed-asset regression for sparse MUL animation frames that previously
/// aborted the complete world render. Does not alter the client assets.
@main struct CheckSparseAnimations {
    static func main() throws {
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let animations = try require(assets.animations)
        let valid = try animations.frame(body: 201, direction: 3, action: 4, frame: 0)
        precondition(valid != nil)
        for frame in 1...2 {
            let absent = try animations.frame(body: 201, direction: 3, action: 4, frame: frame)
            precondition(absent == nil)
        }
        let mobile = WorldMobile(serial: 1, body: 201, x: 3647, y: 2653, z: 0, direction: 3)
        for frame in 0...2 {
            let pose = MobilePresentation(x: 3647, y: 2653, z: 0, walking: false, frame: frame, action: 4)
            let image = try WorldRenderer.render(assets, x: 3647, y: 2653,
                mobiles: [mobile], mobilePresentations: [1: pose])
            precondition(image.landCount > 100 && image.staticCount > 0)
            precondition(image.rgba.contains { $0 > 64 })
        }
        print("Sparse animal animation frames leave terrain/statics rendered; valid neighboring frame still decodes")
    }
    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw AssetError("Animation assets missing") }
        return value
    }
}
