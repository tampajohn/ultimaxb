import Foundation
public enum ToolReach {
    /// Tool use approaches a neighboring tile. A cliff target's Z is not a
    /// walkable destination elevation; the server remains authoritative on use.
    public static func needsApproach(playerX:Int,playerY:Int,target:TargetSelection)->Bool {
        max(abs(playerX-target.x),abs(playerY-target.y))>1
    }
}
