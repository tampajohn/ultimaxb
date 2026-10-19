import Foundation
public enum TravelSafety {
    private static func distance(_ point:WalkPoint,_ enemy:WorldMobile)->Int { max(abs(point.x-enemy.x),abs(point.y-enemy.y)) }
    public static func penalty(_ point:WalkPoint,enemies:[WorldMobile])->Int {
        enemies.filter { abs($0.z-point.z)<=16 }.map { max(0,10-distance(point,$0))*4 }.max() ?? 0
    }
    /// Conservative estimate, not a guarantee of monster speed or intent.
    /// Reserve four tiles for the pickup pause and two tiles of enemy travel
    /// per player step, including turns/latency. Do not assume walls protect us.
    public static func pickupIsSafe(from start:WalkPoint,target:WalkPoint,path:[WalkPoint],enemies:[WorldMobile])->Bool {
        let itemDistance=max(abs(target.x-start.x),abs(target.y-start.y))
        guard itemDistance<=6,path.count<=6,path.count<=itemDistance+2 else { return false }
        for enemy in enemies {
            guard distance(start,enemy)>itemDistance+2,distance(start,enemy)>4 else { return false }
            for (index,point) in path.enumerated() {
                if distance(point,enemy)<=4+2*(index+1) { return false }
            }
        }
        return true
    }
    /// Prefer clearance without turning a moving group into an impassable wall.
    /// Cap the extra walking so successive sections cannot chase ever wider detours.
    public static func route(from start:WalkPoint,to goal:WalkPoint,enemies:[WorldMobile],
                             cost:(WalkPoint)->Int,step:(WalkPoint,UInt8)->WalkPoint?)->[WalkPoint]? {
        guard let direct=WalkPath.find(from:start,x:goal.x,y:goal.y,goalZ:goal.z,limit:8192,travelCost:cost,step:step) else { return nil }
        guard !enemies.isEmpty else { return direct }
        let safer=WalkPath.find(from:start,x:goal.x,y:goal.y,goalZ:goal.z,limit:8192,travelCost:{
            cost($0)+min(8,penalty($0,enemies:enemies)/4)
        },step:step)
        guard let safer,safer.count<=direct.count+max(6,direct.count/2) else { return direct }
        return safer
    }
}
