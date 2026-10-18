import XCTest
@testable import UOCore

final class MobileMotionTests: XCTestCase {
    private func cat(_ x: Int, _ y: Int = 20, z: Int = 0, direction: UInt8 = 2) -> WorldMobile {
        WorldMobile(serial: 1, body: 201, x: x, y: y, z: z, direction: direction)
    }
    func testMovementInterpolatesAndStopsAtExactServerPosition() throws {
        var motion = MobileMotion()
        motion.update([cat(10)], at: 0)
        motion.update([cat(11, z: 4)], at: 1)
        let start = try XCTUnwrap(motion.presentations(at: 1)[1])
        let halfway = try XCTUnwrap(motion.presentations(at: 1.1)[1])
        XCTAssertEqual(start.x, 10)
        XCTAssertEqual(halfway.x, 10.5, accuracy: 0.00001)
        XCTAssertEqual(halfway.z, 2, accuracy: 0.00001)
        XCTAssertTrue(halfway.walking)
        XCTAssertTrue(motion.isAnimating(at: 1.1))
        let end = try XCTUnwrap(motion.presentations(at: 1.21)[1])
        XCTAssertEqual(end.x, 11)
        XCTAssertEqual(end.z, 4)
        XCTAssertFalse(end.walking)
        XCTAssertFalse(motion.isAnimating(at: 1.21))
    }
    func testInterruptedMotionStartsFromDisplayedPosition() throws {
        var motion = MobileMotion()
        motion.update([cat(10)], at: 0)
        motion.update([cat(11)], at: 1)
        let current = try XCTUnwrap(motion.presentations(at: 1.1)[1])
        motion.update([cat(12)], at: 1.1)
        let next = try XCTUnwrap(motion.presentations(at: 1.1)[1])
        XCTAssertEqual(current.x, next.x)
        XCTAssertEqual(motion.presentations(at: 1.2)[1]!.x, 11.25, accuracy: 0.00001)
        // Repeated snapshots from unrelated item updates must not restart motion.
        motion.update([cat(12)], at: 1.2)
        XCTAssertEqual(motion.presentations(at: 1.31)[1]?.x, 12)
        XCTAssertFalse(motion.isAnimating(at: 1.31))
    }
    func testTeleportsAndRemovalDoNotLeaveMovingGhosts() throws {
        var motion = MobileMotion()
        motion.update([cat(10)], at: 0)
        motion.update([cat(100)], at: 1)
        XCTAssertEqual(motion.presentations(at: 1)[1]?.x, 100)
        XCTAssertFalse(motion.isAnimating(at: 1))
        motion.update([], at: 2)
        XCTAssertTrue(motion.presentations(at: 2).isEmpty)
    }
    func testRunningUsesShorterInterpolationAndAnimationAdvances() throws {
        var motion = MobileMotion()
        motion.update([cat(10)], at: 0)
        motion.update([cat(11, direction: 0x82)], at: 1)
        XCTAssertEqual(motion.presentations(at: 1.05)[1]!.x, 10.5, accuracy: 0.00001)
        XCTAssertFalse(motion.isAnimating(at: 1.11))
        motion.update([cat(12)], at: 2)
        XCTAssertGreaterThan(motion.presentations(at: 2.15)[1]!.frame, 0)
    }
}
