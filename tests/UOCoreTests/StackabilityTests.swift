import XCTest
@testable import UOCore

final class StackabilityTests: XCTestCase {
    func testStackableFlagIsIndependentOfEquipmentAndAmount() throws {
        try AssetTests().withClient { root in
            var data = Data(repeating: 0, count: 512*836+1188)
            let start = 512*836+4
            data[start+1] = 8 // Graphic 0: stackable flag 0x0800.
            data[start+37+5] = 1 // Graphic 1: weapon layer, no stackable flag.
            try data.write(to: root.appendingPathComponent("TILEDATA.MUL"))
            let assets = try ClientAssets(directory: root)
            XCTAssertTrue(try assets.isStackable(graphic: 0))
            XCTAssertFalse(try assets.isStackable(graphic: 1))
            XCTAssertEqual(try assets.equipmentLayer(graphic: 1), 1)
        }
    }
}
