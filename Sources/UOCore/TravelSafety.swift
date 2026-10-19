import Foundation
public enum TravelSafety {
    private static func distance(_ point:WalkPoint,_ enemy:WorldMobile)->Int { max(abs(point.x-enemy.x),abs(point.y-enemy.y)) }
    public static func allows(from:WalkPoint,to:WalkPoint,enemies:[WorldMobile])->Bool {
        !enemies.contains { enemy in
            abs(enemy.z-to.z)<=16 && distance(to,enemy)<=5 && distance(to,enemy)<=distance(from,enemy)
        }
    }
    public static func penalty(_ point:WalkPoint,enemies:[WorldMobile])->Int {
        enemies.filter { abs($0.z-point.z)<=16 }.map { max(0,10-distance(point,$0))*4 }.max() ?? 0
    }
}
