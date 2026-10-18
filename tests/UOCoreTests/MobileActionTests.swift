import XCTest
@testable import UOCore
final class MobileActionTests: XCTestCase {
    func command(backward:UInt8 = 0, repeats:UInt8 = 1) throws -> MobileAction {
        try MobileAction.decode(Data([0x6E,0,0,0,1,0,11,0,4,0,repeats,backward,0,0]))
    }
    func testActionFramesExpireAndMovementCancels() throws {
        var motion = MobileMotion()
        motion.update([WorldMobile(serial:1,body:400,x:10,y:10,z:0)],at:0)
        motion.play(try command(),frames:4,at:1)
        XCTAssertEqual(motion.presentations(at:1.33)[1]?.action,11)
        XCTAssertEqual(motion.presentations(at:1.33)[1]?.frame,2)
        XCTAssertNil(motion.presentations(at:1.65)[1]?.action)
        XCTAssertFalse(motion.isAnimating(at:1.65))
        motion.play(try command(backward:1,repeats:0),frames:4,at:2)
        XCTAssertEqual(motion.presentations(at:2)[1]?.frame,3)
        XCTAssertTrue(motion.isAnimating(at:10))
        motion.update([WorldMobile(serial:1,body:400,x:11,y:10,z:0)],at:10)
        XCTAssertNil(motion.presentations(at:10)[1]?.action)
        XCTAssertThrowsError(try MobileAction.decode(Data([0x6E])))
    }
    func testWireValuesDoNotDisconnectForUnavailableAnimations() throws {
        let command = try MobileAction.decode(Data([0x6E,0,0,0,1,255,255,255,255,0,1,255,255,0]))
        XCTAssertEqual(command.action,65535)
        XCTAssertEqual(command.frameCount,65535)
        XCTAssertTrue(command.backward); XCTAssertTrue(command.repeatAnimation)
        var motion = MobileMotion()
        motion.update([WorldMobile(serial:1,body:400,x:0,y:0,z:0)],at:0)
        motion.play(command,frames:4,at:0)
        XCTAssertLessThan(try XCTUnwrap(motion.presentations(at:0)[1]?.frame),4)
    }
    func testGroundDropHasSentinelAndSignedHeight() throws {
        let packet = try InteractionPackets.drop(serial:1,x:2600,y:463,container:0xFFFFFFFF,z:-5)
        XCTAssertEqual(packet,Data([8,0,0,0,1,10,40,1,207,251,255,255,255,255]))
        XCTAssertThrowsError(try InteractionPackets.drop(serial:1,x:1,y:1,container:0xFFFFFFFF,z:128))
    }
}
