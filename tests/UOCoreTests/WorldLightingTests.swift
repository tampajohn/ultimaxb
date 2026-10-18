import XCTest
@testable import UOCore
final class WorldLightingTests:XCTestCase {
    func testAmbientAndPersonalLight() throws {
        var light = WorldLighting()
        XCTAssertEqual(light.brightness,1)
        try light.apply(Data([0x4F,20]),player:1)
        XCTAssertEqual(light.brightness,12.0/32)
        XCTAssertFalse(try light.apply(Data([0x4E,0,0,0,2,30]),player:1))
        XCTAssertEqual(light.personal,0)
        try light.apply(Data([0x4E,0,0,0,1,15]),player:1)
        XCTAssertEqual(light.brightness,15.0/32)
        try light.apply(Data([0x4E,0,0,0,1,30]),player:1)
        XCTAssertEqual(light.brightness,1)
        try light.apply(Data([0x4F,255]),player:1)
        XCTAssertEqual(light.overall,30)
        try light.apply(Data([0x4E,0,0,0,1,0]),player:1)
        XCTAssertEqual(light.brightness,2.0/32)
        light = WorldLighting()
        XCTAssertEqual(light.brightness,1)
    }
    func testMalformedAndUnrelatedPackets() throws {
        var light = WorldLighting()
        for packet in [Data([0x4F]),Data([0x4F,0,0]),Data([0x4E,0,0,0,1]),Data([0x4E,0,0,0,1,1,1])] {
            XCTAssertThrowsError(try light.apply(packet,player:1))
        }
        XCTAssertFalse(try light.apply(Data([0x55]),player:1))
        XCTAssertFalse(try light.apply(Data([0x4E,0,0,0,1,30]),player:nil))
        XCTAssertEqual(light,WorldLighting())
    }
}
