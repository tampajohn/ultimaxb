import Foundation

/// A map click has no height. Resolve it by walking the local collision graph
/// from the selected animal, so bridge decks and slopes use a reachable level.
/// This previews ordinary ground movement; server-specific animal rules win.
public enum HerdingDestination {
    public static func resolve(from start:WalkPoint,x:Int,y:Int,limit:Int=8192,
                               step:(WalkPoint,UInt8)->WalkPoint?)->WalkPoint? {
        guard (0..<6144).contains(x),(0..<4096).contains(y),(-128...127).contains(start.z),
              let path=WalkPath.find(from:start,x:x,y:y,limit:limit,step:step) else { return nil }
        let result=path.last ?? start
        guard result.x==x,result.y==y,(-128...127).contains(result.z) else { return nil }
        return result
    }
}
