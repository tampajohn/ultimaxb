import Foundation
import UOCore
@main struct Check {
 static func main() throws {
  let assets = try ClientAssets(directory:URL(fileURLWithPath:"uo1998-client"))
  let start = WalkPoint(x:2477,y:411,z:15)
  let began = Date()
  let map = try NavigationMap(assets:assets,center:start,additional:[])
  var found = 0
  for (dx,dy) in [(0,5),(5,0),(0,-5),(-5,0)] {
   if let route = WalkPath.find(from:start,x:start.x+dx,y:start.y+dy,step:{ map.step(from:$0,direction:$1) }) {
    var last = start
    for next in route {
     let direction = WalkPath.direction(from:last,to:next)!
     precondition(map.step(from:last,direction:direction) == next)
     last = next
    }
    precondition(last.x == start.x+dx && last.y == start.y+dy)
    found += 1
    print("Minoc route to \(last.x),\(last.y): \(route.count) collision-checked steps")
   }
  }
  precondition(found > 0)
  print("Local map + four searches: \(Int(Date().timeIntervalSince(began)*1000)) ms")
 }
}
