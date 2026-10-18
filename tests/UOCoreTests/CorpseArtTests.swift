import XCTest
@testable import UOCore
final class CorpseArtTests:XCTestCase {
    func testCorpseBodyAndDirectionSurviveWorldProjection() throws {
        let packet = Data([0x1A,0,17,0xC0,0,0,1,0x20,0x06,1,0x90,0x80,100,0,100,3,0])
        var world = WorldState(); XCTAssertTrue(try world.apply(packet))
        let item = try XCTUnwrap(world.items[0x40000001])
        XCTAssertEqual(item.amount,400); XCTAssertEqual(item.direction,3)
        let tile = try XCTUnwrap(world.groundTiles.first)
        XCTAssertEqual(tile.corpseBody,400); XCTAssertEqual(tile.corpseDirection,3)
        XCTAssertEqual(tile.art,0x6006)
        XCTAssertEqual(CorpseArt.deathAction(body:1),2)
        XCTAssertEqual(CorpseArt.deathAction(body:200),8)
        XCTAssertEqual(CorpseArt.deathAction(body:400),21)
    }
}
