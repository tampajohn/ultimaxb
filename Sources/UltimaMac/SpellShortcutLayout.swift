import Foundation

/// UI preferences only: never persists spell contents or assumes book ownership.
final class SpellShortcutLayout {
    struct Entry:Codable,Equatable {
        let book:UInt32
        let spell:Int
        let x:Double
        let y:Double
        var valid:Bool { book != 0 && book != .max && (1...64).contains(spell) && x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
    }
    private let defaults:UserDefaults
    init(defaults:UserDefaults = UserDefaults(suiteName:"com.ultimaxb.UltimaMac")!) { self.defaults=defaults }
    func entries(scope:String)->[Entry] {
        guard let data=defaults.data(forKey:"spellShortcuts.v1.\(scope)"),data.count<=32768,
              let entries=try? JSONDecoder().decode([Entry].self,from:data) else { return [] }
        var keys=Set<UInt64>()
        return Array(entries.filter { $0.valid && keys.insert(UInt64($0.book)<<32 | UInt64($0.spell)).inserted }.prefix(64))
    }
    func save(_ entry:Entry,scope:String) {
        guard entry.valid else { return }
        var values=entries(scope:scope).filter { $0.book != entry.book || $0.spell != entry.spell }
        guard values.count<64 else { return }
        values.append(entry); write(values,scope:scope)
    }
    func remove(book:UInt32,spell:Int,scope:String) {
        write(entries(scope:scope).filter { $0.book != book || $0.spell != spell },scope:scope)
    }
    private func write(_ values:[Entry],scope:String) {
        guard let data=try? JSONEncoder().encode(values) else { return }
        defaults.set(data,forKey:"spellShortcuts.v1.\(scope)")
    }
}
