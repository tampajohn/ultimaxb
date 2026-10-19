import Foundation
@testable import UOCore

@main struct CheckLightOcclusion {
    static func main() throws {
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        var lighting = WorldLighting()
        try lighting.apply(Data([0x4F, 22]), player: 1)
        let wall = try (0..<0x1000).first { graphic in
            let flags = try assets.itemFlags(graphic: graphic)
            return try flags & 0x10 != 0 && flags & (0x04 | 0x800000) == 0 &&
                !assets.isNoDraw(graphic: graphic) && assets.sprite(graphic + 0x4000) != nil
        }!
        let foreground = WorldTile(x: 2494, y: 483, z: 20, art: wall + 0x4000, hue: 0)
        var lamp = WorldTile(x: 2493, y: 482, z: 15, art: 0x4B20, hue: 0)
        func render(_ pattern: Int, wall: Bool, visibility: WorldVisibility = WorldVisibility(), day: Bool = false) throws -> Frame {
            lamp.lightID = pattern
            return try WorldRenderer.render(assets, x: 2493, y: 482,
                visibility: visibility, groundItems: [lamp] + (wall ? [foreground] : []),
                lighting: day ? WorldLighting() : lighting)
        }
        let open = try render(0, wall: false), openUnlit = try render(255, wall: false)
        precondition(open.rgba != openUnlit.rgba, "Unobstructed lamp must contribute light")
        let blocked = try render(0, wall: true), blockedUnlit = try render(255, wall: true)
        precondition(blocked.rgba == blockedUnlit.rgba, "Foreground wall must suppress the light mask")
        let cutaway = WorldVisibility(ceiling: 20, ceilingCells: [.init(x: 2494, y: 483)])
        let interior = try render(0, wall: true, visibility: cutaway)
        let interiorUnlit = try render(255, wall: true, visibility: cutaway)
        precondition(interior.rgba != interiorUnlit.rgba, "Cutaway wall must no longer suppress light")
        let day = try render(0, wall: true, day: true), dayUnlit = try render(255, wall: true, day: true)
        precondition(day.rgba == dayUnlit.rgba, "Occlusion must not alter daylight")
        print("Installed art: foreground wall suppresses light; cutaway restores it; daylight unchanged")
    }
}
