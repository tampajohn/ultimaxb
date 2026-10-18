import XCTest
@testable import UOCore
final class StaticAnimationsTests:XCTestCase {
    func record(_ graphic:Int,offsets:[Int8],interval:UInt8 = 1)->Data {
        let start = graphic*68+(graphic/8+1)*4
        var data = Data(repeating:0,count:start+68)
        for (i,value) in offsets.enumerated() { data[start+i] = UInt8(bitPattern:value) }
        data[start+65] = UInt8(offsets.count); data[start+66] = interval
        return data
    }
    func testSignedOffsetsGroupHeaderAndTiming() throws {
        let anim = try StaticAnimations(data:record(8,offsets:[0,2,-1],interval:2))
        XCTAssertEqual(anim.graphic(8,at:0),8)
        XCTAssertEqual(anim.graphic(8,at:0.17),10)
        XCTAssertEqual(anim.graphic(8,at:0.33),7)
        XCTAssertEqual(anim.graphic(8,at:0.49),8)
        XCTAssertEqual(anim.graphic(7,at:0.17),7)
        let zero = try StaticAnimations(data:record(8,offsets:[0,1],interval:0))
        XCTAssertEqual(zero.graphic(8,at:0.09),9)
    }
    func testMalformedRecordsAndClockValuesFallBack() throws {
        let data = record(0,offsets:[-1,1])
        let anim = try StaticAnimations(data:data)
        XCTAssertEqual(anim.graphic(0,at:0),0)
        for time in [Double.nan,Double.infinity,-1] { XCTAssertEqual(anim.graphic(0,at:time),0) }
        XCTAssertTrue((0...1).contains(anim.graphic(0,at:Double.greatestFiniteMagnitude)))
        XCTAssertEqual(anim.graphic(-1,at:0),-1)
        XCTAssertEqual(anim.graphic(0x4000,at:0),0x4000)
        XCTAssertEqual(try StaticAnimations(data:data.dropLast()).graphic(0,at:0.09),0)
        var invalid = data; invalid[69] = 65
        XCTAssertEqual(try StaticAnimations(data:invalid).graphic(0,at:0.09),0)
        XCTAssertThrowsError(try StaticAnimations(data:Data(repeating:0,count:2*1024*1024+1)))
    }
}
