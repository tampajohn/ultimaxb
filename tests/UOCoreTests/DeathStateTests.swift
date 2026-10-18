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
        XCTAssertEqual(state.phase,.alive)
        try state.apply(Data([0x2C,0]))
        XCTAssertEqual(try state.response(resurrect:false),Data([0x2C,0]))
        XCTAssertEqual(state.phase,.ghost)
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
