import Foundation

public enum ClassicSpells {
    public static let names = [
        "Clumsy","Create Food","Feeblemind","Heal","Magic Arrow","Night Sight","Reactive Armor","Weaken",
        "Agility","Cunning","Cure","Harm","Magic Trap","Magic Untrap","Protection","Strength",
        "Bless","Fireball","Magic Lock","Poison","Telekinesis","Teleport","Unlock","Wall of Stone",
        "Arch Cure","Arch Protection","Curse","Fire Field","Greater Heal","Lightning","Mana Drain","Recall",
        "Blade Spirits","Dispel Field","Incognito","Magic Reflection","Mind Blast","Paralyze","Poison Field","Summon Creature",
        "Dispel","Energy Bolt","Explosion","Invisibility","Mark","Mass Curse","Paralyze Field","Reveal",
        "Chain Lightning","Energy Field","Flame Strike","Gate Travel","Mana Vampire","Mass Dispel","Meteor Swarm","Polymorph",
        "Earthquake","Energy Vortex","Resurrection","Air Elemental","Summon Daemon","Earth Elemental","Fire Elemental","Water Elemental"
    ]
    /// Legacy spellbook contents use each child item's amount as its 1-based spell ID.
    public static func contents(book:UInt32,items:[ContainerItem])->Set<Int> {
        Set(items.filter { $0.container == book && (1...64).contains($0.amount) }.map(\.amount))
    }
    /// OUO HandlePacket_MACRO subtype 0x27: spell ID plus book serial in decimal.
    public static func cast(id:Int,book:UInt32) throws -> Data {
        guard (1...64).contains(id), book != 0, book != 0xFFFFFFFF else { throw LoginProtocolError.malformedPacket }
        let text = Array("\(id) \(book)".utf8)+[0]
        let length = text.count+4
        return Data([0x12,UInt8(length>>8),UInt8(length&255),0x27]+text)
    }
}
