import Foundation
import UOCore
@main struct Check {
 static func main() throws {
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let tiles = try assets.multis!.tiles(id:0,x:2466,y:577,z:0)
  precondition(tiles.contains { $0.art == 0x7EDD })
  let frame = try WorldRenderer.render(assets,x:2466,y:577,groundItems:tiles)
  try frame.writeBMP(to:URL(fileURLWithPath:"build/boat-root.bmp"))
  print("Boat fixture: mast present, \(tiles.count) components, \(frame.missingCount) missing sprites")
 }
}
