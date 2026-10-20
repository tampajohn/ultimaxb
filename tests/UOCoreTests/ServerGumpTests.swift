import XCTest
@testable import UOCore

final class ServerGumpTests: XCTestCase {
    private func fixture() -> Data {
        let layout = Array("{ page 0 }{ resizepic 0 0 5054 300 200 }{ text 20 20 0 0 }{ button 20 80 4005 4007 1 0 7 }\0".utf8)
        var bytes: [UInt8] = [0xB0,0,0]
        bytes += LoginPackets.seed(0x12345678) + LoginPackets.seed(42)
        bytes += LoginPackets.seed(UInt32.max) + LoginPackets.seed(120)
        bytes += [0,UInt8(layout.count)] + layout
        bytes += [0,1,0,3,0,65,0xD8,0x3D,0xDE,0x00]
        bytes[1] = UInt8(bytes.count >> 8); bytes[2] = UInt8(bytes.count & 255)
        return Data(bytes)
    }
    func testDecodeAndReply() throws {
        let gump = try ServerGump.decode(fixture())
        XCTAssertEqual(gump.x,-1); XCTAssertEqual(gump.y,120)
        XCTAssertEqual(gump.commands.count,4)
        XCTAssertEqual(gump.commands.last?.arguments.last,"7")
        XCTAssertEqual(gump.texts,["A😀"])
        let reply = try gump.response(button:7,switches:[9],entries:[(4,"A😀")])
        XCTAssertEqual(Array(reply),[0xB1,0,37,0x12,0x34,0x56,0x78,0,0,0,42,0,0,0,7,0,0,0,1,0,0,0,9,0,0,0,1,0,4,0,3,0,65,0xD8,0x3D,0xDE,0])
        XCTAssertEqual(try gump.response(button:0,switches:[],entries:[]).count,23)
    }
    func testReplyMustMatchAdvertisedControls() throws {
        let gump = try ServerGump.decode(fixture())
        XCTAssertNoThrow(try gump.validatedResponse(button:7,switches:[],entries:[]))
        XCTAssertNoThrow(try gump.validatedResponse(button:0,switches:[],entries:[]))
        XCTAssertThrowsError(try gump.validatedResponse(button:8,switches:[],entries:[]))
        XCTAssertThrowsError(try gump.validatedResponse(button:7,switches:[9],entries:[]))
        XCTAssertThrowsError(try gump.validatedResponse(button:7,switches:[],entries:[(1,"unadvertised")]))
    }
    func testMalformedAndBounds() throws {
        let packet = fixture(), gump = try ServerGump.decode(packet)
        for count in 0..<packet.count { XCTAssertThrowsError(try ServerGump.decode(packet.prefix(count))) }
        XCTAssertThrowsError(try ServerGump.decode(packet + Data([0])))
        for layout in ["{ page 0", "page 0", "{ { page 0 } }", "{ text @unterminated }"] {
            XCTAssertThrowsError(try ServerGump.parseLayout(layout))
        }
        let commands = try ServerGump.parseLayout("{ custom @hello { world }@ }")
        XCTAssertEqual(commands.first?.arguments,["@hello { world }@"])
        XCTAssertThrowsError(try gump.response(button:1,switches:[1,1],entries:[]))
        XCTAssertThrowsError(try gump.response(button:1,switches:[],entries:[(1,"a"),(1,"b")]))
        XCTAssertThrowsError(try gump.response(button:1,switches:[],entries:[(1,String(repeating:"x",count:32768))]))
    }
    func testLimitedEntriesValidateUTF16AndAdvertisedFields() throws {
        let gump=ServerGump(serial:1,id:2,x:0,y:0,commands:try ServerGump.parseLayout("{ textentrylimited 0 0 100 20 0 4 0 3 }{ button 0 30 1 2 1 0 7 }"),texts:[""])
        XCTAssertNoThrow(try gump.validatedResponse(button:7,switches:[],entries:[(4,"A😀")]))
        XCTAssertThrowsError(try gump.validatedResponse(button:7,switches:[],entries:[(4,"AB😀")]))
        XCTAssertThrowsError(try gump.validatedResponse(button:7,switches:[],entries:[]))
        XCTAssertThrowsError(try gump.validatedResponse(button:7,switches:[],entries:[(5,"A")]))
    }
    func testZeroLimitMatchesUnlimitedReferenceAndInvalidLimitIsIgnored() throws {
        for limit in [0,-1,65536] {
            let gump=ServerGump(serial:1,id:2,x:0,y:0,commands:try ServerGump.parseLayout("{ textentrylimited 0 0 100 20 0 4 0 \(limit) }"),texts:[""])
            if limit==0 { XCTAssertNoThrow(try gump.validatedResponse(button:0,switches:[],entries:[(4,"Longer text")])) }
            else { XCTAssertThrowsError(try gump.validatedResponse(button:0,switches:[],entries:[(4,"")])) }
        }
    }
    func testLimitedTextPreservesSurrogatePairs() {
        XCTAssertEqual(ServerGump.limitedText("A😀BC",units:3),"A😀")
        XCTAssertEqual(ServerGump.limitedText("A😀BC",units:2),"A")
        XCTAssertEqual(ServerGump.limitedText("😀",units:1),"")
        XCTAssertEqual(ServerGump.limitedText("Hello",units:0),"")
    }

}
