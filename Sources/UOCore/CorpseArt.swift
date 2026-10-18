import Foundation

/// The 0x2006 world item stores its creature body in the amount field.
/// Corpses use the final frame of the body's classic death animation.
public enum CorpseArt {
    public static func deathAction(body:Int) -> Int { body < 200 ? 2 : (body < 400 ? 8 : 21) }
    public static func frame(body:Int,direction:UInt8,assets:ClientAssets) throws -> AnimationFrame? {
        let action = deathAction(body:body)
        guard let count = try assets.animations?.frameCount(body:body,direction:direction,action:action) else { return nil }
        return try assets.animations?.frame(body:body,direction:direction,action:action,frame:count-1)
    }
}
