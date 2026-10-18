import XCTest
@testable import UOCore
final class ServerMenuTests:XCTestCase {
    func fixture(graphic:UInt8 = 10)->Data {
        var bytes:[UInt8] = [0x7C,0,0,0x40,0,0,1,0,9,3,65,120,101,2]
        bytes += [0,graphic,0,5,3,79,110,101, 0,11,0,6,3,84,119,111]
        bytes[2] = UInt8(bytes.count); return Data(bytes)
    }
    func testDecodeAndExactChoiceCancelResponses() throws {
        let menu = try ServerMenu.decode(fixture())
        XCTAssertEqual(menu.title,"Axe"); XCTAssertEqual(menu.options.map(\.title),["One","Two"])
        XCTAssertEqual(try menu.response(choice:2),Data([0x7D,0x40,0,0,1,0,9,0,2,0,11,0,6]))
        XCTAssertEqual(try menu.response(choice:0),Data([0x7D,0x40,0,0,1,0,9,0,0,0,0,0,0]))
        XCTAssertThrowsError(try menu.response(choice:3)); XCTAssertThrowsError(try menu.response(choice:-1))
        let text = try ServerMenu.decode(fixture(graphic:0))
        XCTAssertFalse(text.usesIcons)
        XCTAssertEqual(try text.response(choice:2).suffix(4),Data([0,0,0,0]))
    }
    func testTruncationAndFragmentedFraming() throws {
        let packet = fixture()
        for length in 0..<packet.count { XCTAssertThrowsError(try ServerMenu.decode(packet.prefix(length))) }
        var extra = packet; extra.append(0); extra[2] += 1
        XCTAssertThrowsError(try ServerMenu.decode(extra))
        var framer = GamePacketFramer()
        XCTAssertEqual(try framer.receive(packet.prefix(7)),[])
        XCTAssertEqual(try framer.receive(packet.dropFirst(7)),[packet])
    }
}
