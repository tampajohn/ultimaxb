import XCTest
@testable import UOCore
final class CombatTargetTests:XCTestCase {
    func testTargetHealthAndLifecycle() throws {
        var target = CombatTarget()
        XCTAssertTrue(try target.apply(Data([0x30,0,0,0,7])))
        XCTAssertEqual(target.serial,7)
        XCTAssertNil(target.status?.health)
        XCTAssertFalse(try target.apply(Data([0xA1,0,0,0,8,0,100,0,40])))
        XCTAssertTrue(try target.apply(Data([0xA1,0,0,0,7,0,100,0,40])))
        XCTAssertEqual(target.status?.health,40)
        XCTAssertFalse(try target.apply(Data([0x30,0,0,0,7])))
        XCTAssertEqual(target.status?.health,40)
        XCTAssertTrue(try target.apply(Data([0xAA,0,0,0,9])))
        XCTAssertNil(target.status?.health)
        XCTAssertFalse(try target.apply(Data([0x1D,0,0,0,7])))
        XCTAssertTrue(try target.apply(Data([0x1D,0,0,0,9])))
        XCTAssertNil(target.serial)
        for end in [Data([0x31]),Data([0x72,0,0,0,0]),Data([0xAA,0,0,0,0])] {
            try target.apply(Data([0xAA,0,0,0,1]))
            XCTAssertTrue(try target.apply(end)); XCTAssertNil(target.serial)
        }
    }
    func testFragmentedConfirmationAndNamedStatus() throws {
        var status = Data([0x11,0,43,0,0,0,7])
        status.append(contentsOf:Array("Test creature".utf8))
        status.append(contentsOf:repeatElement(0,count:30-13))
        status.append(contentsOf:[0,35,0,100,0,0])
        let stream = Data([0xAA,0,0,0,7])+status
        for split in 0...stream.count {
            var framer = GamePacketFramer(), target = CombatTarget()
            let packets = try framer.receive(Data(stream.prefix(split))) + framer.receive(Data(stream.dropFirst(split)))
            for packet in packets { try target.apply(packet) }
            XCTAssertEqual(target.name,"Test creature")
            XCTAssertEqual(target.status?.health,35)
            XCTAssertEqual(target.status?.maxHealth,100)
            var unrelated = status; unrelated[6] = 8
            XCTAssertFalse(try target.apply(unrelated))
            XCTAssertEqual(target.name,"Test creature")
        }
    }
    func testMalformedPreservesTarget() throws {
        var target = CombatTarget()
        try target.apply(Data([0x30,0,0,0,7]))
        let before = target
        for packet in [Data([0x30]),Data([0x31,0]),Data([0xAA,0x40,0,0,1]),Data([0x11,0,43]),Data([0x72,2,0,0,0])] {
            XCTAssertThrowsError(try target.apply(packet))
            XCTAssertEqual(target,before)
        }
    }
}
