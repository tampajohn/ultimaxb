import Foundation
@testable import UOCore
@main struct CheckLightPatterns {
    static func main() throws {
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let graphic = 0xB20
        let normal = try assets.lightIndex(graphic: graphic)
        precondition(normal == 29)
        let overridden = try assets.lightIndex(graphic: graphic, override: 0)
        precondition(overridden == 0)
        let invalid = try assets.lightIndex(graphic: graphic, override: 255)
        precondition(invalid == nil)
        let unlit = try assets.lightIndex(graphic: 0xB21, override: 0)
        precondition(unlit == nil, "A light pattern must not turn an unlit item into a lamp")
        var lighting = WorldLighting()
        try lighting.apply(Data([0x4F,22]),player:1)
        var tile = WorldTile(x:2493,y:482,z:15,art:graphic+0x4000,hue:0)
        let defaultFrame = try WorldRenderer.render(assets,x:2493,y:482,groundItems:[tile],lighting:lighting)
        tile.lightID = 0
        let dynamicFrame = try WorldRenderer.render(assets,x:2493,y:482,groundItems:[tile],lighting:lighting)
        precondition(defaultFrame.rgba != dynamicFrame.rgba)
        precondition(defaultFrame.landCount == dynamicFrame.landCount && defaultFrame.staticCount == dynamicFrame.staticCount)
        let dayDefault = try WorldRenderer.render(assets,x:2493,y:482,groundItems:[tile])
        tile.lightID = nil
        let dayStatic = try WorldRenderer.render(assets,x:2493,y:482,groundItems:[tile])
        precondition(dayDefault.rgba == dayStatic.rgba, "Light masks must not change daylight sprites")
        print("Server light patterns alter nighttime illumination, preserve map defaults and leave daylight unchanged")
    }
}
