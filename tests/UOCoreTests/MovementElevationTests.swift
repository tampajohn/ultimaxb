import Foundation
import XCTest
@testable import UOCore

final class MovementElevationTests: XCTestCase {
    func testStairsCoverBuriedGroundAndUseHalfBridgeHeight() throws {
        try AssetTests().withClient { root in
            // Three stair treads and an unreachable overhead floor.
            let statics = Data([1,0,2,2,0,0,0, 1,0,3,2,5,0,0, 1,0,4,2,10,0,0,
                                2,0,2,2,30,0,0])
            try statics.write(to: root.appendingPathComponent("STATICS0.MUL"))
            let index = try FileHandle(forWritingTo: root.appendingPathComponent("STAIDX0.MUL"))
            try index.seek(toOffset: UInt64(513 * 12))
            try index.write(contentsOf: AssetTests().words([0,0,statics.count,0,0,0])); try index.close()
            var metadata = Data(repeating: 0, count: 512*836+1188)
            let stair = 512*836+4+37
            metadata[stair+1] = 6 // Surface + Bridge: climb at half of height 5.
            metadata[stair+16] = 5
            metadata[stair+37+1] = 2
            metadata[stair+37+16] = 5
            try metadata.write(to: root.appendingPathComponent("TILEDATA.MUL"))
            let assets = try ClientAssets(directory: root)
            XCTAssertEqual(try assets.predictedStepZ(x: 10, y: 10, fromZ: 0), 2)
            XCTAssertEqual(try assets.predictedStepZ(x: 11, y: 10, fromZ: 2), 7)
            XCTAssertEqual(try assets.predictedStepZ(x: 12, y: 10, fromZ: 7), 12)
            XCTAssertEqual(try assets.predictedStepZ(x: 11, y: 10, fromZ: 12), 7)
            XCTAssertEqual(try assets.predictedStepZ(x: 10, y: 10, fromZ: 7), 2)
        }
    }
}
