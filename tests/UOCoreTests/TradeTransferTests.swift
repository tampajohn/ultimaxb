import XCTest
@testable import UOCore
final class TradeTransferTests:XCTestCase {
    func update(serial:UInt32 = 3,container:UInt32 = 10)->Data {
        Data([0x25]+LoginPackets.seed(serial)+[0x0E,0xED,0,0,1,0,10,0,10]+LoginPackets.seed(container)+[0,0])
    }
    func testDeleteAndAcknowledgementCannotUnlockStaleOffer() throws {
        var transfer = TradeTransfer(item:3,destination:10)
        try transfer.receive(Data([0x1D,0,0,0,3]))
        XCTAssertFalse(transfer.complete)
        try transfer.receive(Data([0x29]))
        XCTAssertFalse(transfer.complete)
        try transfer.receive(update(container:99)); XCTAssertFalse(transfer.complete)
        try transfer.receive(update()); XCTAssertTrue(transfer.complete)
    }
    func testDestinationBeforeAcknowledgementAndStackMerge() throws {
        var transfer = TradeTransfer(item:3,destination:10)
        try transfer.receive(update()); XCTAssertFalse(transfer.complete)
        try transfer.receive(Data([0x29])); XCTAssertTrue(transfer.complete)
        var merged = TradeTransfer(item:3,destination:5)
        try merged.receive(update(serial:5,container:10))
        XCTAssertFalse(merged.complete)
        try merged.receive(Data([0x29])); XCTAssertTrue(merged.complete)
    }
    func ground(serial:UInt32 = 3)->Data {
        Data([0x1A,0,14] + LoginPackets.seed(serial) + [0x0E,0xED,0,10,0,10,0])
    }
    func testGroundUpdateDoesNotConfirmContainerDestination() throws {
        var transfer = TradeTransfer(item:3,destination:10)
        try transfer.receive(ground())
        try transfer.receive(Data([0x29]))
        XCTAssertFalse(transfer.complete)
        try transfer.receive(update())
        XCTAssertTrue(transfer.complete)
        var drop = TradeTransfer(item:3,destination:UInt32.max)
        try drop.receive(ground())
        try drop.receive(Data([0x29]))
        XCTAssertTrue(drop.complete)
    }
    func testRejectedDropWaitsForReturnedItemWithoutRequiringAcknowledgement() throws {
        var transfer = TradeTransfer(item:3,destination:10)
        try transfer.receive(Data([0x28,0,10,0,10]))
        try transfer.receive(Data([0x29]))
        try transfer.receive(ground(serial:4))
        XCTAssertFalse(transfer.complete)
        try transfer.receive(ground())
        XCTAssertTrue(transfer.complete)
        var bounced = TradeTransfer(item:3,destination:10)
        try bounced.receive(update(container:99))
        try bounced.receive(Data([0x28,0,10,0,10]))
        XCTAssertFalse(bounced.complete)
        try bounced.receive(update(serial:4,container:99))
        XCTAssertFalse(bounced.complete)
        try bounced.receive(update(container:99))
        XCTAssertTrue(bounced.complete)
    }
    func testEquipmentWithdrawalWaitsForMatchingOwnerAndSerial() throws {
        func equip(_ serial:UInt32,_ owner:UInt32)->Data {
            Data([0x2E] + LoginPackets.seed(serial) + [0x0F,0x43,0,1] + LoginPackets.seed(owner) + [0,0])
        }
        var transfer = TradeTransfer(item:3,destination:1)
        try transfer.receive(Data([0x29]))
        try transfer.receive(equip(4,1)); XCTAssertFalse(transfer.complete)
        try transfer.receive(equip(3,2)); XCTAssertFalse(transfer.complete)
        try transfer.receive(equip(3,1)); XCTAssertTrue(transfer.complete)
        var first = TradeTransfer(item:3,destination:1)
        try first.receive(equip(3,1)); XCTAssertFalse(first.complete)
        try first.receive(Data([0x29])); XCTAssertTrue(first.complete)
    }
    func testRejectionAndMalformedPackets() throws {
        var transfer = TradeTransfer(item:3,destination:10)
        XCTAssertThrowsError(try transfer.receive(Data([0x29,0])))
        XCTAssertFalse(transfer.complete)
        try transfer.receive(Data([0x27,0])); XCTAssertTrue(transfer.complete)
    }
}
