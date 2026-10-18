import XCTest
@testable import UOCore
final class TextPromptTests:XCTestCase {
    func testASCIIReplyAndCancel() throws {
        let packet = Data([0x9A,0,16,0,0,0,1,0,0,0,2,0,0,0,0,0])
        let prompt = try TextPrompt.decode(packet)
        XCTAssertEqual(try prompt.response(text:"abc",accepted:true),Data([0x9A,0,19,0,0,0,1,0,0,0,2,0,0,0,1,97,98,99,0]))
        XCTAssertEqual(try prompt.response(text:"discard",accepted:false),packet)
        XCTAssertThrowsError(try prompt.response(text:"😀",accepted:true))
        XCTAssertThrowsError(try prompt.response(text:"a\0b",accepted:true))
        XCTAssertThrowsError(try prompt.response(text:String(repeating:"a",count:240),accepted:true))
    }
    func testNumericDialogLimitsAndIdentity() throws {
        let packet = Data([0xAB,0,19,0,0,0,1,2,3,0,0,1,2,0,0,0,50,0,0])
        let prompt = try TextPrompt.decode(packet)
        XCTAssertEqual(try prompt.response(text:"50",accepted:true),Data([0xAC,0,15,0,0,0,1,2,3,1,0,3,53,48,0]))
        for value in ["51","-1","","1.0","999999999999999999999"] { XCTAssertThrowsError(try prompt.response(text:value,accepted:true)) }
        for length in 0..<packet.count { XCTAssertThrowsError(try TextPrompt.decode(packet.prefix(length))) }
        var noCancel = packet; noCancel[11] = 0
        XCTAssertThrowsError(try TextPrompt.decode(noCancel).response(text:"",accepted:false))
    }
}
