import XCTest
@testable import UOCore
final class SkillTests: XCTestCase {
    func testLegacyListAndUpdateAtomicity() throws {
        var state = SkillState()
        try state.apply(Data([0x3A,0,14,0,0,1,1,244,0,2,2,88,0,0]))
        XCTAssertEqual(state.values,[0:500,1:600])
        try state.apply(Data([0x3A,0,8,255,0,1,2,89]))
        XCTAssertEqual(state.values,[0:500,1:601])
        XCTAssertThrowsError(try state.apply(Data([0x3A,0,8,0,0,1,0,5])))
        XCTAssertEqual(state.values,[0:500,1:601])
        XCTAssertThrowsError(try state.apply(Data([0x3A,0,10,255,0,1,2,89,0,0])))
    }
    func testRequests() throws {
        XCTAssertEqual(SkillState.request(serial:0x12345678),Data([0x34,237,237,237,237,5,0x12,0x34,0x56,0x78]))
        XCTAssertEqual(try SkillState.use(id:1),Data([0x12,0,8,0x24,49,32,48,0]))
        XCTAssertThrowsError(try SkillState.use(id:-1))
    }
    func testDefinitions() throws {
        let values = try SkillAssets.decode(index:Data([0,0,0,0,5,0,0,0,0,0,0,0]),data:Data([1,65,66,67,0]))
        XCTAssertEqual(values.first?.name,"ABC"); XCTAssertEqual(values.first?.usable,true)
        XCTAssertThrowsError(try SkillAssets.decode(index:Data([0]),data:Data()))
    }
}
