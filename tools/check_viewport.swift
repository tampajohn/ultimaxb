import Foundation
import UOCore
@main struct CheckViewport {
 static func main() throws {
    let assets=try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
    let camera=WorldCamera(x:2477,y:411)
    let base=try WorldRenderer.render(assets,x:2477,y:411)
    for width in [640,1440,2048] {
        let frame=try WorldRenderer.render(assets,x:2477,y:411,width:width,height:720)
        // Shared central terrain must remain pixel-identical: change the field of view, not sprite geometry.
        for y in 200..<520 { for x in 380..<580 {
            let a=(y*960+x)*4, b=(y*width+x+(width-960)/2)*4
            precondition(base.rgba[a..<a+4] == frame.rgba[b..<b+4])
        } }
        for (x,y) in [(480.0,382.0),(400,450),(600,500)] {
            let a=try WorldHitTest.location(assets:assets,camera:camera,screenX:x,screenY:y,visibility:WorldVisibility())
            let b=try WorldHitTest.location(assets:assets,camera:camera,screenX:x+Double((width-960)/2),screenY:y,visibility:WorldVisibility(),width:width,height:720)
            precondition(a?.x == b?.x && a?.y == b?.y && a?.z == b?.z)
        }
    }
    print("Variable-width terrain preserves central pixels and terrain picking at 640, 1440 and 2048 pixels")
 }
}
