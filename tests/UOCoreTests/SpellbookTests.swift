import XCTest
@testable import UOCore
final class SpellbookTests:XCTestCase {
    func testContentsAreBookScopedAndUseSpellAmounts() throws {
        func item(_ serial:UInt32,_ id:Int,_ book:UInt32)->ContainerItem {
            ContainerItem(serial:serial,graphic:0x1F2D,amount:id,x:0,y:0,container:book,hue:0)
        }
        XCTAssertEqual(ClassicSpells.contents(book:100,items:[item(1,4,100),item(2,64,100),item(3,4,100),item(4,65,100),item(5,0,100),item(6,1,200)]),[4,64])
        XCTAssertEqual(ClassicSpells.names.count,64)
        XCTAssertEqual(ClassicSpells.names[3],"Heal")
        XCTAssertEqual(ClassicSpells.names[58],"Resurrection")
    }
    func testLegacyCastMacroAndFraming() throws {
        let packet = try ClassicSpells.cast(id:4,book:0x40000001)
        let text = Array("4 1073741825".utf8)+[UInt8(0)]
        XCTAssertEqual(packet,Data([0x12,0,UInt8(4+text.count),0x27]+text))
        var framer = GamePacketFramer()
        XCTAssertEqual(try framer.receive(packet.prefix(5)),[])
        XCTAssertEqual(try framer.receive(packet.dropFirst(5)),[packet])
        XCTAssertThrowsError(try ClassicSpells.cast(id:0,book:1))
        XCTAssertThrowsError(try ClassicSpells.cast(id:65,book:1))
        XCTAssertThrowsError(try ClassicSpells.cast(id:1,book:0))
    }
}
