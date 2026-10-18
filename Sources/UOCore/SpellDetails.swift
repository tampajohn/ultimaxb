// Spell metadata adapted from ClassicUO SpellsMagery.cs (BSD-2-Clause).
// See LICENSES/ClassicUO.txt. Original book icons are 0x08C0...0x08FF.
import Foundation

public extension ClassicSpells {
    struct Detail {
        public let words:String
        public let reagents:[String]
        public let icon:Int
    }
    static func detail(id:Int)->Detail? {
        guard (1...64).contains(id) else { return nil }
        let value = descriptions[id-1]
        return Detail(words:value.0,reagents:value.1,icon:0x8C0+id-1)
    }
    private static let descriptions:[(String,[String])] = [
        ("Uus Jux",["Bloodmoss", "Nightshade"]),
        ("In Mani Ylem",["Garlic", "Ginseng", "Mandrake Root"]),
        ("Rel Wis",["Nightshade", "Ginseng"]),
        ("In Mani",["Garlic", "Ginseng", "Spider’s Silk"]),
        ("In Por Ylem",["Sulfurous Ash"]),
        ("In Lor",["Spider’s Silk", "Sulfurous Ash"]),
        ("Flam Sanct",["Garlic", "Spider’s Silk", "Sulfurous Ash"]),
        ("Des Mani",["Garlic", "Nightshade"]),
        ("Ex Uus",["Bloodmoss", "Mandrake Root"]),
        ("Uus Wis",["Nightshade", "Mandrake Root"]),
        ("An Nox",["Garlic", "Ginseng"]),
        ("An Mani",["Nightshade", "Spider’s Silk"]),
        ("In Jux",["Garlic", "Spider’s Silk", "Sulfurous Ash"]),
        ("An Jux",["Bloodmoss", "Sulfurous Ash"]),
        ("Uus Sanct",["Garlic", "Ginseng", "Sulfurous Ash"]),
        ("Uus Mani",["Mandrake Root", "Nightshade"]),
        ("Rel Sanct",["Garlic", "Mandrake Root"]),
        ("Vas Flam",["Black Pearl"]),
        ("An Por",["Bloodmoss", "Garlic", "Sulfurous Ash"]),
        ("In Nox",["Nightshade"]),
        ("Ort Por Ylem",["Bloodmoss", "Mandrake Root"]),
        ("Rel Por",["Bloodmoss", "Mandrake Root"]),
        ("Ex Por",["Bloodmoss", "Sulfurous Ash"]),
        ("In Sanct Ylem",["Bloodmoss", "Garlic"]),
        ("Vas An Nox",["Garlic", "Ginseng", "Mandrake Root"]),
        ("Vas Uus Sanct",["Garlic", "Ginseng", "Mandrake Root", "Sulfurous Ash"]),
        ("Des Sanct",["Garlic", "Nightshade", "Sulfurous Ash"]),
        ("In Flam Grav",["Black Pearl", "Spider’s Silk", "Sulfurous Ash"]),
        ("In Vas Mani",["Garlic", "Ginseng", "Mandrake Root", "Spider’s Silk"]),
        ("Por Ort Grav",["Mandrake Root", "Sulfurous Ash"]),
        ("Ort Rel",["Black Pearl", "Mandrake Root", "Spider’s Silk"]),
        ("Kal Ort Por",["Black Pearl", "Bloodmoss", "Mandrake Root"]),
        ("In Jux Hur Ylem",["Black Pearl", "Mandrake Root", "Nightshade"]),
        ("An Grav",["Black Pearl", "Garlic", "Spider’s Silk", "Sulfurous Ash"]),
        ("Kal In Ex",["Bloodmoss", "Garlic", "Nightshade"]),
        ("In Jux Sanct",["Garlic", "Mandrake Root", "Spider’s Silk"]),
        ("Por Corp Wis",["Black Pearl", "Mandrake Root", "Nightshade", "Sulfurous Ash"]),
        ("An Ex Por",["Garlic", "Mandrake Root", "Spider’s Silk"]),
        ("In Nox Grav",["Black Pearl", "Nightshade", "Spider’s Silk"]),
        ("Kal Xen",["Bloodmoss", "Mandrake Root", "Spider’s Silk"]),
        ("An Ort",["Garlic", "Mandrake Root", "Sulfurous Ash"]),
        ("Corp Por",["Black Pearl", "Nightshade"]),
        ("Vas Ort Flam",["Bloodmoss", "Mandrake Root"]),
        ("An Lor Xen",["Bloodmoss", "Nightshade"]),
        ("Kal Por Ylem",["Black Pearl", "Bloodmoss", "Mandrake Root"]),
        ("Vas Des Sanct",["Garlic", "Mandrake Root", "Nightshade", "Sulfurous Ash"]),
        ("In Ex Grav",["Black Pearl", "Ginseng", "Spider’s Silk"]),
        ("Wis Quas",["Bloodmoss", "Sulfurous Ash"]),
        ("Vas Ort Grav",["Black Pearl", "Bloodmoss", "Mandrake Root", "Sulfurous Ash"]),
        ("In Sanct Grav",["Black Pearl", "Mandrake Root", "Spider’s Silk", "Sulfurous Ash"]),
        ("Kal Vas Flam",["Spider’s Silk", "Sulfurous Ash"]),
        ("Vas Rel Por",["Black Pearl", "Mandrake Root", "Sulfurous Ash"]),
        ("Ort Sanct",["Black Pearl", "Bloodmoss", "Mandrake Root", "Spider’s Silk"]),
        ("Vas An Ort",["Black Pearl", "Garlic", "Mandrake Root", "Sulfurous Ash"]),
        ("Flam Kal Des Ylem",["Bloodmoss", "Mandrake Root", "Spider’s Silk", "Sulfurous Ash"]),
        ("Vas Ylem Rel",["Bloodmoss", "Mandrake Root", "Spider’s Silk"]),
        ("In Vas Por",["Bloodmoss", "Ginseng", "Mandrake Root", "Sulfurous Ash"]),
        ("Vas Corp Por",["Black Pearl", "Bloodmoss", "Mandrake Root", "Nightshade"]),
        ("An Corp",["Bloodmoss", "Ginseng", "Garlic"]),
        ("Kal Vas Xen Hur",["Bloodmoss", "Mandrake Root", "Spider’s Silk"]),
        ("Kal Vas Xen Corp",["Bloodmoss", "Mandrake Root", "Spider’s Silk", "Sulfurous Ash"]),
        ("Kal Vas Xen Ylem",["Bloodmoss", "Mandrake Root", "Spider’s Silk"]),
        ("Kal Vas Xen Flam",["Bloodmoss", "Mandrake Root", "Spider’s Silk", "Sulfurous Ash"]),
        ("Kal Vas Xen An Flam",["Bloodmoss", "Mandrake Root", "Spider’s Silk"]),
    ]
}
