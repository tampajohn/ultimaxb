import XCTest
@testable import UOCore
final class DeathStateTests:XCTestCase {
    func testExplicitChoiceWaitsForServerConfirmation() throws {
        var state = DeathState()
        XCTAssertThrowsError(try state.response(resurrect:true))
        XCTAssertTrue(try state.apply(Data([0x2C,0])))
        XCTAssertEqual(state.phase,.offered)
        XCTAssertEqual(try state.response(resurrect:true),Data([0x2C,1]))
        XCTAssertEqual(state.phase,.awaitingResurrection)
        XCTAssertThrowsError(try state.response(resurrect:true))
        try state.apply(Data([0x2C,1]))
        XCTAssertEqual(state.phase,.ghost, "Dialog dismissal does not prove resurrection succeeded")
        XCTAssertTrue(state.apply(player: WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 0)))
        XCTAssertEqual(state.phase,.alive)
        try state.apply(Data([0x2C,0]))
        XCTAssertEqual(try state.response(resurrect:false),Data([0x2C,0]))
        XCTAssertEqual(state.phase,.ghost)
    }
    func testGhostLoginAndHealerResurrectionWithoutDeathDialog() {
        for (ghost, living) in [(402, 400), (403, 401)] {
            var state = DeathState()
            XCTAssertTrue(state.apply(player: WorldMobile(serial: 1, body: ghost, x: 10, y: 10, z: 0)))
            XCTAssertEqual(state.phase, .ghost)
            XCTAssertFalse(state.apply(player: WorldMobile(serial: 1, body: ghost, x: 11, y: 10, z: 0)))
            XCTAssertTrue(state.apply(player: WorldMobile(serial: 1, body: living, x: 11, y: 10, z: 0)))
            XCTAssertEqual(state.phase, .alive)
        }
    }
    func testGhostUpdatesPreserveExplicitChoiceAndDismissalOrdering() throws {
        var state = DeathState()
        let ghost = WorldMobile(serial: 1, body: 402, x: 10, y: 10, z: 0)
        let alive = WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 0)
        _ = state.apply(player: ghost)
        try state.apply(Data([0x2C, 0]))
        XCTAssertFalse(state.apply(player: ghost))
        XCTAssertEqual(state.phase, .offered)
        _ = try state.response(resurrect: true)
        XCTAssertFalse(state.apply(player: ghost))
        XCTAssertEqual(state.phase, .awaitingResurrection)
        XCTAssertTrue(state.apply(player: alive))
        try state.apply(Data([0x2C, 1]))
        XCTAssertEqual(state.phase, .alive, "Late dialog dismissal must not resurrect a stale ghost state")
    }
    func testMalformedPacketsDoNotChangeState() throws {
        var state = DeathState()
        try state.apply(Data([0x2C,0]))
        for packet in [Data([0x2C]),Data([0x2C,2]),Data([0x2C,0,0])] {
            XCTAssertThrowsError(try state.apply(packet))
            XCTAssertEqual(state.phase,.offered)
        }
        XCTAssertFalse(try state.apply(Data([0x55])))
        var framer = GamePacketFramer()
        XCTAssertEqual(try framer.receive(Data([0x2C])),[])
        XCTAssertEqual(try framer.receive(Data([0])),[Data([0x2C,0])])
    }
}
