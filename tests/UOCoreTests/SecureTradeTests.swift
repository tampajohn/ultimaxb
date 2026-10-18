import XCTest
@testable import UOCore
final class SecureTradeTests:XCTestCase {
    func packet(_ action:UInt8,_ serial:UInt32,_ first:UInt32 = 0,_ second:UInt32 = 0,name:String? = nil)->Data {
        var data = Data([0x6F,0,name == nil ? 17 : 47,action]+LoginPackets.seed(serial)+LoginPackets.seed(first)+LoginPackets.seed(second)+[name == nil ? 0 : 1])
        if let name { let bytes = Array(name.utf8.prefix(30)); data.append(contentsOf:bytes+Array(repeating:0,count:30-bytes.count)) }
        return data
    }
    func item(_ serial:UInt32 = 3,amount:Int = 1,container:UInt32 = 10)->ContainerItem {
        ContainerItem(serial:serial,graphic:0xEED,amount:amount,x:10,y:10,container:container,hue:0)
    }
    func testOpeningAcceptanceAndCancellationWire() throws {
        let event = try TradeEvent.decode(packet(0,1,10,20,name:"Trader"))
        var trade = try XCTUnwrap(SecureTrade(event:event))
        XCTAssertEqual(trade.partnerName,"Trader"); XCTAssertEqual(trade.ownContainer,10)
        XCTAssertEqual(try trade.setAccepted(true,revision:0),packet(2,10,1))
        XCTAssertFalse(trade.ownAccepted); XCTAssertEqual(trade.pendingAcceptance,true)
        XCTAssertThrowsError(try trade.setAccepted(true,revision:0))
        trade.apply(try TradeEvent.decode(packet(2,10,1,0)))
        XCTAssertTrue(trade.ownAccepted); XCTAssertNil(trade.pendingAcceptance)
        XCTAssertEqual(try trade.cancel(),packet(1,10))
        XCTAssertThrowsError(try trade.cancel())
        trade.apply(try TradeEvent.decode(packet(1,20)))
        XCTAssertTrue(trade.closed); XCTAssertThrowsError(try trade.setAccepted(true,revision:0))
    }
    func testOfferChangesRevokeAcceptanceAndRejectStaleClicks() throws {
        var trade = SecureTrade(event:.opened(partner:1,ownContainer:10,otherContainer:20,name:""))!
        trade.update(items:[item()])
        XCTAssertEqual(trade.revision,1)
        _ = try trade.setAccepted(true,revision:1)
        XCTAssertEqual(trade.update(items:[item(amount:2)]),packet(2,10,0))
        XCTAssertEqual(trade.revision,2); XCTAssertFalse(trade.ownAccepted)
        trade.apply(.acceptance(container:10,own:true,other:true))
        XCTAssertFalse(trade.ownAccepted); XCTAssertEqual(trade.pendingAcceptance,false)
        trade.apply(.acceptance(container:10,own:false,other:false))
        XCTAssertNil(trade.pendingAcceptance)
        XCTAssertThrowsError(try trade.setAccepted(true,revision:1))
        XCTAssertNoThrow(try trade.setAccepted(true,revision:2))
    }
    func testNestedChangesAndUnrelatedState() throws {
        var trade = SecureTrade(event:.opened(partner:1,ownContainer:10,otherContainer:20,name:""))!
        trade.update(items:[item(),item(4,container:3),item(5,container:999)])
        XCTAssertEqual(trade.items.map(\.serial),[3,4]); let revision = trade.revision
        trade.update(items:[item(4,container:3),item()])
        XCTAssertEqual(trade.revision,revision)
        trade.apply(.closed(container:999)); XCTAssertFalse(trade.closed)
        trade.update(items:[item(),item(4,amount:2,container:3)])
        XCTAssertEqual(trade.revision,revision+1)
    }
    func testMalformedPackets() throws {
        let valid = packet(0,1,10,20,name:"Trader")
        for length in 0..<valid.count { XCTAssertThrowsError(try TradeEvent.decode(valid.prefix(length))) }
        XCTAssertThrowsError(try TradeEvent.decode(valid+Data([0])))
        XCTAssertThrowsError(try TradeEvent.decode(packet(0,1,10,10)))
        XCTAssertThrowsError(try TradeEvent.decode(packet(7,1)))
    }
}
