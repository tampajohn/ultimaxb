import Foundation

/// Classic client allocation: 60 stat points and 100 skill points across three skills.
public struct CharacterAllocation: Equatable, Sendable {
    public var strength: Int = 30
    public var dexterity: Int = 15
    public var intelligence: Int = 15
    public var skillIDs: [Int] = [27,40,17]
    public var skillValues: [Int] = [50,50,0]
    public init() {}
    public var validationMessage: String? {
        guard [strength,dexterity,intelligence].allSatisfy({ (10...45).contains($0) }) else { return "Each stat must be between 10 and 45." }
        guard strength+dexterity+intelligence == 60 else { return "Allocate exactly 60 stat points (currently \(strength+dexterity+intelligence))." }
        guard skillIDs.count == 3, Set(skillIDs).count == 3, skillIDs.allSatisfy({ (0..<49).contains($0) }) else { return "Choose three different starting skills." }
        guard skillValues.count == 3, skillValues.allSatisfy({ (0...50).contains($0) }), skillValues.reduce(0,+) == 100 else { return "Allocate 100 skill points, with at most 50 in each skill." }
        return nil
    }
}

public struct CharacterAppearance: Equatable, Sendable {
    public var skinHue = 0x3EA
    public var hairStyle = 0
    public var hairHue = 0x44E
    public var beardStyle = 0
    public var beardHue = 0x44E
    public init() {}
    public static let hairStyles = [0,0x203B,0x203C,0x203D,0x2044,0x2045,0x2046,0x2047,0x2048,0x2049,0x204A]
    public static let beardStyles = [0,0x203E,0x203F,0x2040,0x2041,0x204B,0x204C,0x204D]
    public func isValid(female:Bool) -> Bool {
        (0x3EA...0x422).contains(skinHue) && (0x44E...0x47D).contains(hairHue) && (0x44E...0x47D).contains(beardHue)
        && Self.hairStyles.contains(hairStyle) && Self.beardStyles.contains(beardStyle)
        && (!female || beardStyle == 0) && (female || hairStyle != 0x2046)
    }
    public var equipment: [EquippedItem] {
        var items: [EquippedItem] = []
        if hairStyle != 0 { items.append(EquippedItem(serial:2,graphic:hairStyle,layer:11,owner:1,hue:hairHue)) }
        if beardStyle != 0 { items.append(EquippedItem(serial:3,graphic:beardStyle,layer:16,owner:1,hue:beardHue)) }
        return items
    }
}
