import Foundation
import XCTest
@testable import UOCore

final class WorldVisibilityTests: XCTestCase {
    func testSlopeEntryUsesLowEdgeRatherThanAverageAsStepBarrier() throws {
        try AssetTests().withClient { root in
            let map = try FileHandle(forWritingTo: root.appendingPathComponent("MAP0.MUL"))
            for (x,y,z) in [(10,10,13),(11,10,10),(11,11,15),(10,11,15)] {
                let offset = ((x / 8) * 512 + y / 8) * 196 + 4 + ((y % 8) * 8 + x % 8) * 3
                try map.seek(toOffset: UInt64(offset)); try map.write(contentsOf: Data([3,0,UInt8(z)]))
            }
            try map.close()
            let assets = try ClientAssets(directory: root)
            XCTAssertEqual(try assets.predictedStepZ(x: 10, y: 10, fromZ: 2), 14)
            XCTAssertEqual(try assets.predictedStepZ(x: 10, y: 10, fromZ: 0), 0)
        }
    }
    func testOverheadTerrainIsHiddenOnlyWhenUnderneath() throws {
        try AssetTests().withClient { root in
            let map = try FileHandle(forWritingTo: root.appendingPathComponent("MAP0.MUL"))
            let blockOffset: Int = 513 * 196 + 4
            let cellOffset: Int = 18 * 3
            try map.seek(toOffset: UInt64(blockOffset + cellOffset))
            try map.write(contentsOf: Data([3,0,30])); try map.close()
            let assets = try ClientAssets(directory: root)
            let inside = try WorldVisibility.around(player: WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 0), assets: assets)
            XCTAssertTrue(inside.hides(z: 30))
            XCTAssertTrue(inside.hidesTerrain(z: 30))
            XCTAssertFalse(inside.hides(z: 0))
            let outside = try WorldVisibility.around(player: WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 30), assets: assets)
            XCTAssertNil(outside.ceiling)
        }
    }
    func testRoofTriggersCutawayButNearbyRoofDoesNot() throws {
        try AssetTests().withClient { root in
            try Data([1,0,2,2,35,0,0]).write(to: root.appendingPathComponent("STATICS0.MUL"))
            let index = try FileHandle(forWritingTo: root.appendingPathComponent("STAIDX0.MUL"))
            try index.seek(toOffset: UInt64((512+1)*12))
            try index.write(contentsOf: AssetTests().words([0,0,7,0,0,0])); try index.close()
            var metadata = Data(repeating: 0, count: 512*836+1188)
            metadata[512*836+4+37+3] = 0x10
            try metadata.write(to: root.appendingPathComponent("TILEDATA.MUL"))
            let assets = try ClientAssets(directory: root)
            let indoors = try WorldVisibility.around(player: WorldMobile(serial: 1, body: 400, x: 10, y: 10, z: 15), assets: assets)
            XCTAssertNotNil(indoors.ceiling)
            XCTAssertFalse(indoors.hidesTerrain(z: 40), "Roof cutaway must preserve surrounding hills")
            XCTAssertNil(try WorldVisibility.around(player: WorldMobile(serial: 1, body: 400, x: 11, y: 10, z: 15), assets: assets).ceiling)
        }
    }
}
