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
    func testRejectionAndMalformedPackets() throws {
        var transfer = TradeTransfer(item:3,destination:10)
        XCTAssertThrowsError(try transfer.receive(Data([0x29,0])))
        XCTAssertFalse(transfer.complete)
        try transfer.receive(Data([0x27,0])); XCTAssertTrue(transfer.complete)
    }
}
