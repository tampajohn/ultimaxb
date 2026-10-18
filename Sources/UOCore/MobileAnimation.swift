import Foundation

/// Classic MUL human animation selection, shared by rendering and pointer hit testing.
/// Group selection follows ClassicUO MobileAnimation.cs (BSD-2-Clause; LICENSES/ClassicUO.txt).
public enum MobileAnimation {
    private static let twoHandedStances: Set<Int> = [0x263,0x264,0x265,0x266,0x267,0x268,0x269,0x26D,0x270,0x272,0x274,0x27A,0x27C,0x27F,0x281,0x286,0x288,0x289,0x28B]
    public static func action(body:Int, war:Bool, walking:Bool, running:Bool,
                              firstHand:Bool = false, secondHandAnimation:Int? = nil,
                              serverAction:Int? = nil) -> Int {
        if let serverAction { return serverAction }
        guard body == 400 || body == 401 else {
            return walking ? (running && body >= 200 ? (body >= 400 ? 2 : 1) : 0) : (body < 200 ? 1 : (body < 400 ? 2 : 4))
        }
        if walking {
            if war && !running { return 15 }
            return running ? (secondHandAnimation == nil ? 2 : 3) : (secondHandAnimation == nil ? 0 : 1)
        }
        guard war else { return 4 }
        return !firstHand && secondHandAnimation.map { twoHandedStances.contains($0) } == true ? 8 : 7
    }
    public static func action(for mobile:WorldMobile, pose:MobilePresentation?, equipment:[EquippedItem], assets:ClientAssets) throws -> Int {
        let held = equipment.filter { $0.owner == mobile.serial }
        let second = held.first { $0.layer == 2 }
        let animation = try second.flatMap { try assets.equipmentAnimation(graphic:$0.graphic) }
        return action(body:mobile.body,war:mobile.flags & 0x40 != 0,walking:pose?.walking == true,
                      running:mobile.direction & 0x80 != 0,firstHand:held.contains { $0.layer == 1 },
                      secondHandAnimation:animation,serverAction:pose?.action)
    }
}
