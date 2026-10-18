import Foundation
import UOCore
@main struct CheckHiddenMobile {
    static func main() throws {
        let assets = try ClientAssets(directory: URL(fileURLWithPath: "uo1998-client"))
        let visible = WorldMobile(serial: 1, body: 400, x: 2493, y: 482, z: 15, hue: 1002)
        let hidden = WorldMobile(serial: 1, body: 400, x: 2493, y: 482, z: 15, hue: 1002, flags: 0x80)
        let clothes = [EquippedItem(serial: 2, graphic: 0x1517, layer: 5, owner: 1, hue: 1109)]
        let ordinary = try WorldRenderer.render(assets, x: 2493, y: 482, mobiles: [visible], equipment: clothes)
        let concealed = try WorldRenderer.render(assets, x: 2493, y: 482, mobiles: [hidden], equipment: clothes)
        let empty = try WorldRenderer.render(assets, x: 2493, y: 482)
        precondition(ordinary.rgba != concealed.rgba && concealed.rgba != empty.rgba)
        precondition(ordinary.landCount == concealed.landCount && concealed.missingCount == 0)
        let revealed = try WorldRenderer.render(assets, x: 2493, y: 482, mobiles: [visible], equipment: clothes)
        precondition(revealed.rgba == ordinary.rgba, "Revealing must restore original hues")
        try concealed.writeBMP(to: URL(fileURLWithPath: "build/hidden-character.bmp"))
        print("Hidden character remains visible with distinct tint; revealing restores body and clothing hues")
    }
}
