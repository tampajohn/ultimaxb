import XCTest
@testable import UOCore

final class GumpTests: XCTestCase {
    func testRunsAndTransparency() throws {
        let raw = Bytes(Data([1,0,0,0, 0,0,1,0, 0,124,2,0]))
        let sprite = try GumpAssets.decode(raw, width: 3, height: 1)
        XCTAssertEqual(sprite.rgba, [0,0,0,0, 255,0,0,255, 255,0,0,255])
    }
    func testMalformedRunsAndOffsets() {
        for data: [UInt8] in [[0,0,0,0], [1,0,0,0,0,0,0,0], [1,0,0,0,0,0,4,0], [1,0,0,0]] {
            XCTAssertThrowsError(try GumpAssets.decode(Bytes(Data(data)), width: 3, height: 1))
        }
    }
    func testInstalledBackpack() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("uo1998-client")
        guard FileManager.default.fileExists(atPath: directory.path) else { throw XCTSkip("Local assets absent") }
        let assets = try ClientAssets(directory: directory)
        let sprite = try XCTUnwrap(assets.gumps?.sprite(60))
        if let output = ProcessInfo.processInfo.environment["UO_GUMP_PREVIEW"] {
            try Frame(width: sprite.width, height: sprite.height, rgba: sprite.rgba,
                      landCount: 0, staticCount: 0, missingCount: 0, huedCount: 0).writeBMP(to: URL(fileURLWithPath: output))
        }
        XCTAssertGreaterThan(sprite.width, 100)
        XCTAssertGreaterThan(sprite.rgba.filter { $0 != 0 }.count, 1000)
    }
    func testVersionDataOverridesAndAddsGumps() throws {
        func words(_ values: [UInt32]) -> Data {
            Data(values.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> ($0*8)) } })
        }
        let red = Data([1,0,0,0, 0,124,1,0])
        let green = Data([1,0,0,0, 224,3,1,0])
        let index = words([0,8,0x10001])
        // Override an existing record and add one beyond the original index.
        var patch = words([2, 12,0,44,8,0x10001, 12,9,52,8,0x10001])
        patch.append(green); patch.append(red)
        let assets = try GumpAssets(index:index,data:red,verdata:patch)
        XCTAssertEqual(try assets.sprite(0)?.rgba,[0,255,0,255])
        XCTAssertEqual(try assets.sprite(9)?.rgba,[255,0,0,255])
        XCTAssertNil(try assets.sprite(8))
        XCTAssertThrowsError(try GumpAssets(index:index,data:red,verdata:patch.dropLast()))
        XCTAssertThrowsError(try GumpAssets(index:index,data:red,verdata:words([100])))
        let unpatched = try GumpAssets(index:index,data:red)
        XCTAssertEqual(try unpatched.sprite(0)?.rgba,[255,0,0,255])
    }

    func testInstalledCreationPatch() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("data/uo-1.26.0")
        guard FileManager.default.fileExists(atPath:directory.appendingPathComponent("verdata.mul").path) else {
            throw XCTSkip("Local 1.26 assets absent")
        }
        let assets = try ClientAssets(directory:directory)
        let frame = try XCTUnwrap(assets.gumps?.sprite(0x708))
        XCTAssertEqual(frame.width,237); XCTAssertEqual(frame.height,363)
        let body = try XCTUnwrap(assets.gumps?.sprite(0x761))
        XCTAssertEqual(body.width,322); XCTAssertEqual(body.height,294)
        XCTAssertTrue(body.rgba.enumerated().contains { $0.offset % 4 == 3 && $0.element != 0 })
    }

    func testCoinPileGraphic() {
        for (amount, expected) in [(1,0xEED),(2,0xEEE),(5,0xEEE),(6,0xEEF),(100,0xEEF)] {
            let item = ContainerItem(serial: 1, graphic: 0xEED, amount: amount, x: 0, y: 0, container: 2, hue: 0)
            XCTAssertEqual(item.displayGraphic, expected)
        }
    }
}
