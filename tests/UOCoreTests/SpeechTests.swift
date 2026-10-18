import XCTest
@testable import UOCore

final class SpeechTests: XCTestCase {
    func testBankSpeechWireFormat() throws {
        XCTAssertEqual(try SpeechPackets.say("bank"), Data([3,0,13,0,3,0xB2,0,3,98,97,110,107,0]))
        for text in ["", "hi\nthere", String(repeating: "a", count: 201), "😀"] {
            XCTAssertThrowsError(try SpeechPackets.say(text))
        }
    }
    func testSpeechModesAndLiteralPunctuation() throws {
        for (input,type,payload) in [("; hello",8,"hello"),("! hello",9,"hello"),(": waves",2,"*waves*"),("!hello",0,"!hello"),("bank",0,"bank")] {
            let packet = try SpeechPackets.say(input)
            XCTAssertEqual(packet[3],UInt8(type))
            XCTAssertEqual(String(data:packet.dropFirst(8).dropLast(),encoding:.isoLatin1),payload)
            XCTAssertEqual(Int(packet[1])*256+Int(packet[2]),packet.count)
        }
        for input in ["; ",": ","!   ","; hi\nthere",": "+String(repeating:"a",count:199)] {
            XCTAssertThrowsError(try SpeechPackets.say(input))
        }
        XCTAssertNoThrow(try SpeechPackets.say(": "+String(repeating:"a",count:198)))
        XCTAssertEqual(SpeechPackets.mode(for:": waves").label,"Emote")
    }
    func testIncomingSpeechAndTruncation() throws {
        var packet = Data([0x1C,0,50,0,0,0,1,1,0x90,0,3,0xB2,0,3])
        packet.append(Data("Banker".utf8)); packet.append(Data(repeating: 0, count: 24))
        packet.append(Data("Hello".utf8)); packet.append(0)
        let message = try SpeechMessage.decode(packet)
        XCTAssertEqual(message.hue,0x3B2); XCTAssertEqual(message.font,3)
        var overhead = OverheadSpeech(); overhead.append(message,at:0)
        XCTAssertEqual(overhead.entries.first?.hue,0x3B2)
        XCTAssertEqual(message.serial, 1); XCTAssertEqual(message.name, "Banker"); XCTAssertEqual(message.text, "Hello")
        for length in 0..<packet.count { XCTAssertThrowsError(try SpeechMessage.decode(Data(packet.prefix(length)))) }
    }
}
