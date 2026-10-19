import Foundation
import UOCore

@main struct CheckEnemyOutline {
    static func main() throws {
        let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
        let mobile = WorldMobile(serial:1,body:400,x:2603,y:309,z:15,direction:3,notoriety:5)
        let normal = try WorldRenderer.render(assets,x:2603,y:309,width:320,height:240,mobiles:[mobile])
        let outlined = try WorldRenderer.render(assets,x:2603,y:309,width:320,height:240,mobiles:[mobile],outlinedMobiles:[1])
        var changed = 0
        for i in stride(from:0,to:normal.rgba.count,by:4) {
            if normal.rgba[i..<i+4] != outlined.rgba[i..<i+4] {
                changed += 1
                precondition(outlined.rgba[i] == 255 && outlined.rgba[i+1] == 45 && outlined.rgba[i+2] == 45)
            }
        }
        precondition(changed > 30 && changed < 1000,"Outline must be a thin silhouette, not a filled sprite")
        try outlined.writeBMP(to:URL(fileURLWithPath:"build/enemy-outline.bmp"))
        print("Installed asset outline: \(changed) red edge pixels")
    }
}
