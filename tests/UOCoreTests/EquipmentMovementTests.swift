import Foundation
import XCTest
@testable import UOCore

final class EquipmentMovementTests: XCTestCase {
    func testMountedCadenceKeepsSingleTilePredictionAndQueueLimit() throws {
        for running in [false,true] {
            var movement = PlayerMovement()
            let direction:UInt8 = running ? 0x82 : 2
            var player = WorldMobile(serial:1,body:400,x:100,y:100,z:0,direction:direction)
            let interval = running ? 0.1 : 0.2
            for n in 0..<5 {
                let time = Double(n)*interval+0.00001*Double(n)
                XCTAssertNotNil(movement.request(direction:direction,player:player,at:time,mounted:true))
                player = try XCTUnwrap(movement.predictedPosition)
                XCTAssertEqual(player.x,101+n)
                XCTAssertNil(movement.request(direction:direction,player:player,at:time+interval/2,mounted:true))
            }
            XCTAssertNil(movement.request(direction:direction,player:player,at:10,mounted:true))
            _ = try movement.receive(Data([0x22,0,1]),player:player)
            XCTAssertNotNil(movement.request(direction:direction,player:player,at:10,mounted:true))
        }
    }
    func testMovementAcknowledgementsPreserveNewServerAppearance() throws {
        for flags: UInt8 in [0, 0x80, 0x40, 0x04] {
            var movement = PlayerMovement()
            let start = WorldMobile(serial: 1, body: 400, x: 100, y: 100, z: 0, direction: 2, flags: flags ^ 0x80)
            XCTAssertNotNil(movement.request(direction: 2, player: start, at: 0))
            let first = try XCTUnwrap(movement.predictedPosition)
            XCTAssertNotNil(movement.request(direction: 2, player: first, at: 0.5))
            // An appearance update arrives while both movement requests are pending.
            let updated = WorldMobile(serial: 1, body: 401, x: 101, y: 100, z: 0, direction: 2, hue: 1002, flags: flags)
            for sequence: UInt8 in [0, 1] {
                let result = try XCTUnwrap(movement.receive(Data([0x22, sequence, 1]), player: updated))
                XCTAssertEqual(result.x, 102, "Acknowledging an older step must not rewind newer prediction")
                XCTAssertEqual(result.body, updated.body)
                XCTAssertEqual(result.hue, updated.hue)
                XCTAssertEqual(result.flags, updated.flags, "Movement must not restore stale hiding, war or poison flags")
            }
        }
    }
    func testRejectedStepIdentifiesOriginalRequestNotLatestPrediction() throws {
        var movement = PlayerMovement()
        let player = WorldMobile(serial:1,body:400,x:10,y:10,z:0,direction:2)
        XCTAssertNotNil(movement.request(direction:2,player:player,at:0))
        let first = try XCTUnwrap(movement.predictedPosition)
        XCTAssertNotNil(movement.request(direction:2,player:first,at:0.5))
        let latest = try XCTUnwrap(movement.predictedPosition)
        XCTAssertEqual(latest.x,12)
        _ = try movement.receive(Data([0x21,0,0,10,0,10,2,0]),player:latest)
        XCTAssertEqual(movement.rejectedStep,WalkPoint(x:11,y:10,z:0))
        XCTAssertTrue(movement.awaitingPosition)
        XCTAssertNil(movement.request(direction:4,player:player,at:1))
        var turn = PlayerMovement()
        XCTAssertNotNil(turn.request(direction:4,player:player,at:0))
        _ = try turn.receive(Data([0x21,0,0,10,0,10,2,0]),player:player)
        XCTAssertNil(turn.rejectedStep) // A denied turn is not evidence of an obstructed tile.
    }
    func testShortNetworkGapsKeepPlayerAnimationPhase() {
        var motion = MobileMotion()
        func player(_ x: Int) -> WorldMobile { WorldMobile(serial: 1, body: 400, x: x, y: 10, z: 0, direction: 0x82) }
        motion.update([player(10)], at: 0, playerSerial: 1)
        motion.update([player(11)], at: 1, playerSerial: 1)
        XCTAssertTrue(motion.presentations(at: 1.23)[1]!.walking)
        let before = motion.presentations(at: 1.23)[1]!
        motion.update([player(12)], at: 1.23, playerSerial: 1)
        let after = motion.presentations(at: 1.23)[1]!
        XCTAssertEqual(after.frame, before.frame)
        XCTAssertEqual(after.x, before.x)
        XCTAssertGreaterThan(after.frame, 0)
        XCTAssertFalse(motion.presentations(at: 2)[1]!.walking)
        XCTAssertEqual(motion.presentations(at: 2)[1]!.x, 12)
    }
    func testNewOppositeKeyReplacesOldIntentWithoutBreakingDiagonals() {
        var keys = MovementKeys()
        keys.press(126, direction: 7) // Up
        keys.press(124, direction: 1) // Right
        XCTAssertEqual(keys.direction, 0)
        keys.press(125, direction: 3) // Down replaces Up, preserving Right
        XCTAssertEqual(keys.direction, 2)
        keys.release(124)
        XCTAssertEqual(keys.direction, 3)
        keys.release(126) // A late Up release must not affect Down.
        XCTAssertEqual(keys.direction, 3)
        keys.release(125)
        XCTAssertNil(keys.direction)
    }
    func testCombinedKeysCoverEightDirectionsAndCancelOpposites() {
        XCTAssertEqual(MovementInput.direction([7,1]), 0) // W+D
        XCTAssertEqual(MovementInput.direction([7,5]), 6) // W+A
        XCTAssertEqual(MovementInput.direction([3,1]), 2) // S+D
        XCTAssertEqual(MovementInput.direction([3,5]), 4) // S+A
        XCTAssertNil(MovementInput.direction([7,3]))
        XCTAssertNil(MovementInput.direction([1,5]))
        XCTAssertEqual(MovementInput.direction([7,7,1]), 0)
    }
    func testPlayerInterpolationMatchesWalkCadence() {
        var motion = MobileMotion()
        motion.update([WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 0)], at: 0, playerSerial: 1)
        motion.update([WorldMobile(serial: 1, body: 400, x: 11, y: 10, z: 0)], at: 1, playerSerial: 1)
        XCTAssertEqual(motion.presentations(at: 1.2)[1]!.x, 10.5, accuracy: 0.001)
        XCTAssertTrue(motion.presentations(at: 1.3)[1]!.walking)
        XCTAssertEqual(motion.presentations(at: 1.4)[1]!.x, 11, accuracy: 0.001)
    }
    func testEquipmentSurvivesMovementAndFollowsRemovalTransitions() throws {
        var world = WorldState()
        let mobile = MobileTests().naked
        var equipped = Data([0x78,0,32]) + mobile.dropFirst()
        equipped += Data([0x40,0,0,2, 0x9F,3, 11, 0x01,0x23, 0,0,0,0])
        try world.apply(equipped)
        XCTAssertEqual(world.equipment[0x40000002]?.graphic, 0x1F03)
        XCTAssertEqual(world.equipment[0x40000002]?.hue, 0x123)
        try world.apply(mobile)
        XCTAssertEqual(world.equipment.count, 1)
        // Same layer replaces the old item, and reserved/stackable byte is not a graphic increment.
        try world.apply(Data([0x2E,0x40,0,0,3,0x15,0x17,1,11,0,0,0,1,0,5]))
        XCTAssertEqual(world.equipment.count, 1)
        XCTAssertEqual(world.equipment[0x40000003]?.graphic, 0x1517)
        try world.apply(Data([0x1D,0x40,0,0,3]))
        XCTAssertTrue(world.equipment.isEmpty)
        try world.apply(equipped)
        try world.apply(Data([0x1D,0,0,0,1]))
        XCTAssertTrue(world.equipment.isEmpty)
    }
    func testFullEquipmentUpdateClearsRemovedLayers() throws {
        var world = WorldState()
        let equipment = Data([0x2E,0x40,0,0,3,0x15,0x17,0,5,0,0,0,1,0,5])
        try world.apply(equipment)
        let bare = Data([0x78,0,23]) + MobileTests().naked.dropFirst() + Data([0,0,0,0])
        try world.apply(bare)
        XCTAssertTrue(world.equipment.isEmpty)
    }
    func testMovementTurnStepAcknowledgementAndPositionSync() throws {
        var movement = PlayerMovement()
        let player = WorldMobile(serial: 1, body: 400, x: 100, y: 100, z: 10, direction: 3)
        XCTAssertEqual(movement.request(direction: 2, player: player, at: 0), Data([2,2,0]))
        XCTAssertNil(movement.request(direction: 2, player: player, at: 0.05))
        XCTAssertNil(try movement.receive(Data([0x22,9,1]), player: player))
        let turn = try XCTUnwrap(movement.receive(Data([0x22,0,1]), player: player))
        XCTAssertEqual(turn.x, 100)
        XCTAssertEqual(turn.direction, 2)
        XCTAssertEqual(movement.request(direction: 2, player: turn, at: 1), Data([2,2,1]))
        let step = try XCTUnwrap(movement.receive(Data([0x22,1,1]), player: turn))
        XCTAssertEqual(step.x, 101)
        XCTAssertEqual(step.y, 100)
        XCTAssertFalse(movement.awaitingPosition)
        XCTAssertEqual(movement.poll(at: 2), PlayerMovement.requestPosition)
        XCTAssertTrue(movement.awaitingPosition)
    }
    func testPredictionPipelinesWithoutWaitingAndOldAcknowledgementsDoNotRewind() throws {
        var movement = PlayerMovement()
        var player = WorldMobile(serial: 1, body: 400, x: 100, y: 100, z: 0, direction: 0x82)
        for index in 0..<5 {
            XCTAssertNotNil(movement.request(direction: 0x82, player: player, at: Double(index) * 0.21))
            player = try XCTUnwrap(movement.predictedPosition)
            XCTAssertEqual(player.x, 101 + index)
        }
        XCTAssertNil(movement.request(direction: 0x82, player: player, at: 1.5))
        XCTAssertEqual(movement.pendingCount, 5)
        let ack = try XCTUnwrap(movement.receive(Data([0x22,0,1]), player: player))
        XCTAssertEqual(ack.x, 105)
        XCTAssertEqual(movement.pendingCount, 4)
        XCTAssertNil(movement.poll(at: 1))
        XCTAssertEqual(movement.poll(at: 3), PlayerMovement.requestPosition)
        XCTAssertTrue(movement.awaitingPosition)
        XCTAssertNil(movement.poll(at: 4))
    }
    func testDeniedMovementRestoresPositionAndResetsSequence() throws {
        var movement = PlayerMovement()
        let player = WorldMobile(serial: 1, body: 400, x: 100, y: 100, z: 10)
        _ = movement.request(direction: 0, player: player, at: 0)
        let correction = try XCTUnwrap(movement.receive(Data([0x21,0,0,99,0,98,7,0xFD]), player: player))
        XCTAssertEqual(correction.x, 99)
        XCTAssertEqual(correction.y, 98)
        XCTAssertEqual(correction.z, -3)
        XCTAssertEqual(correction.direction, 7)
        XCTAssertNil(movement.request(direction: 7, player: correction, at: 0.5))
        _ = try movement.receive(Data([0x20]) + Data(repeating: 0, count: 18), player: correction)
        XCTAssertEqual(movement.request(direction: 7, player: correction, at: 1), Data([2,7,0]))
        XCTAssertThrowsError(try movement.receive(Data([0x21,0]), player: player))
    }
}
