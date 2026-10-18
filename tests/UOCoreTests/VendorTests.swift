import XCTest
@testable import UOCore
final class VendorTests: XCTestCase {
    func testSellListAndResponse() throws {
        let packet = Data([0x9E,0,27,0,0,0,99,0,1, 0,0,0,20,0x0F,0x5C,0,0,0,1,0,12,0,4,77,97,99,101])
        let result = try VendorPackets.sellOffers(packet)
        XCTAssertEqual(result.vendor,99); XCTAssertEqual(result.offers[0].name,"Mace")
        XCTAssertEqual(result.offers[0].item.graphic,0xF5C); XCTAssertEqual(result.offers[0].price,12)
        XCTAssertEqual(try VendorPackets.sell(vendor:99,offers:result.offers,quantities:[20:1]),Data([0x9F,0,15,0,0,0,99,0,1,0,0,0,20,0,1]))
        XCTAssertThrowsError(try VendorPackets.sell(vendor:99,offers:result.offers,quantities:[20:2]))
        XCTAssertThrowsError(try VendorPackets.sellOffers(packet.dropLast()))
        XCTAssertEqual(VendorPackets.cancelSell(vendor:99),Data([0x9F,0,9,0,0,0,99,0,0]))
        var framer = GamePacketFramer()
        XCTAssertEqual(try framer.receive(packet),[packet])
    }
    func testWireOrderAndPurchaseBounds() throws {
        let a = ContainerItem(serial:20,graphic:0xF43,amount:2,x:0,y:0,container:100,hue:0)
        let b = ContainerItem(serial:10,graphic:0xF44,amount:4,x:0,y:0,container:100,hue:0)
        let data = Data([0x74,0,26,0,0,0,100,2, 0,0,0,40,4,65,120,101,0, 0,0,0,60,4,66,111,119,0])
        let offers = try VendorPackets.offers(data,contents:[a,b])
        XCTAssertEqual(offers.map { $0.item.serial },[10,20]); XCTAssertEqual(offers.map(\.price),[40,60])
        XCTAssertEqual(offers[0].name,"Axe")
        XCTAssertEqual(offers[0].item.graphic,0xF44)
        let purchase = try VendorPackets.buy(vendor:99,offers:offers,quantities:[20:2])
        XCTAssertEqual(purchase,Data([0x3B,0,15,0,0,0,99,2,26,0,0,0,20,0,2]))
        XCTAssertThrowsError(try VendorPackets.buy(vendor:99,offers:offers,quantities:[20:3]))
        XCTAssertThrowsError(try VendorPackets.buy(vendor:99,offers:offers,quantities:[30:1]))
        XCTAssertThrowsError(try VendorPackets.offers(data,contents:[a]))
        XCTAssertThrowsError(try VendorPackets.offers(data.dropLast(),contents:[a,b]))
    }
}
