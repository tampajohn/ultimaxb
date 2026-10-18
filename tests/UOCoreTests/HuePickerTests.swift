import XCTest
@testable import UOCore
final class HuePickerTests:XCTestCase {
    func testWireAndPaletteBounds() throws {
        let request = try HuePicker.decode(Data([0x95,0x12,0x34,0x56,0x78,0x0F,0xAB,0,0]))
        XCTAssertEqual(request.serial,0x12345678); XCTAssertEqual(request.typeID,0x0FAB)
        XCTAssertEqual(try request.response(hue:3),Data([0x95,0x12,0x34,0x56,0x78,0x0F,0xAB,0,3]))
        var hues = Set<Int>()
        for shade in 0...4 { for row in 0..<10 { for column in 0..<20 { hues.insert(HuePicker.hue(column:column,row:row,shade:shade)!) } } }
        XCTAssertEqual(hues,Set(2...1001))
        XCTAssertNil(HuePicker.hue(column:20,row:0,shade:0))
        XCTAssertNil(HuePicker.hue(column:0,row:-1,shade:0))
        XCTAssertNil(HuePicker.hue(column:0,row:0,shade:5))
        XCTAssertThrowsError(try request.response(hue:0)); XCTAssertThrowsError(try request.response(hue:1002))
        XCTAssertThrowsError(try HuePicker.decode(Data([0x95])))
    }
}
