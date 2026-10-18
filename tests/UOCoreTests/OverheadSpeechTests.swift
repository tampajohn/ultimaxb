import XCTest
@testable import UOCore
final class OverheadSpeechTests:XCTestCase {
    func message(_ serial:UInt32,_ text:String,_ type:UInt8 = 0)->SpeechMessage {
        SpeechMessage(serial:serial,type:type,name:"",text:text)
    }
    func testSpeakersStackIndependentlyAndExpire() {
        var speech = OverheadSpeech()
        speech.append(message(1,"Hello"),at:0); speech.append(message(2,"Reply"),at:1)
        speech.append(message(1,"Second"),at:1); speech.append(message(1,"Third"),at:1)
        speech.append(message(1,"Fourth"),at:1)
        XCTAssertEqual(speech.entries.filter { $0.serial == 1 }.map(\.text),["Second","Third","Fourth"])
        XCTAssertEqual(speech.entries.first?.serial,2)
        speech.expire(at:5); XCTAssertTrue(speech.entries.isEmpty)
    }
    func testBoundsLabelsAndSystemMessages() {
        var speech = OverheadSpeech()
        speech.append(message(0,"system"),at:0); speech.append(message(0xFFFFFFFF,"system"),at:0)
        XCTAssertTrue(speech.entries.isEmpty)
        for i in 1...100 { speech.append(message(UInt32(i),String(repeating:"é",count:1000)),at:0) }
        XCTAssertEqual(speech.entries.count,64)
        XCTAssertEqual(speech.entries.last?.text.count,512)
        speech.append(message(100,"Name",6),at:1)
        XCTAssertEqual(speech.entries.filter { $0.serial == 100 }.map(\.text),["Name"])
        speech.expire(at:12); XCTAssertTrue(speech.entries.isEmpty)
    }
}
