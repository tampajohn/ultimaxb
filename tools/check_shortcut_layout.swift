import Foundation

@main struct Check {
    static func main() throws {
        let suite="com.ultimaxb.shortcut-check.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store=SpellShortcutLayout(defaults:defaults)
        let entry=SpellShortcutLayout.Entry(book:100,spell:4,x:0.25,y:0.75)
        store.save(entry,scope:"serverA:character1")
        precondition(SpellShortcutLayout(defaults:defaults).entries(scope:"serverA:character1") == [entry])
        precondition(store.entries(scope:"serverA:character2").isEmpty)
        precondition(store.entries(scope:"serverB:character1").isEmpty)
        store.save(.init(book:100,spell:4,x:0.5,y:0.5),scope:"serverA:character1")
        precondition(store.entries(scope:"serverA:character1").count == 1)
        store.save(.init(book:100,spell:65,x:0.5,y:0.5),scope:"serverA:character1")
        store.save(.init(book:100,spell:5,x:.nan,y:0.5),scope:"serverA:character1")
        precondition(store.entries(scope:"serverA:character1").count == 1)
        let corrupt=[entry,entry,SpellShortcutLayout.Entry(book:0,spell:4,x:0.2,y:0.2)]
        defaults.set(try JSONEncoder().encode(corrupt),forKey:"spellShortcuts.v1.fixture")
        precondition(store.entries(scope:"fixture") == [entry])
        store.remove(book:100,spell:4,scope:"serverA:character1")
        precondition(store.entries(scope:"serverA:character1").isEmpty)
        precondition(store.entries(scope:"fixture") == [entry])
        print("Shortcut layout roundtrip, isolation, replacement, removal and invalid-data filtering passed")
    }
}
