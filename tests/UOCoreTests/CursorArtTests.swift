import XCTest
@testable import UOCore
final class CursorArtTests: XCTestCase {
    func testHotspotMarkersAreNotVisible() {
        var pixels = [UInt8](repeating: 0,count: 5*5*4)
        func put(_ x: Int,_ y: Int,_ rgb:[UInt8]) { pixels.replaceSubrange((y*5+x)*4..<(y*5+x)*4+4,with:rgb+[255]) }
        put(2,0,[0,255,0]); put(0,3,[0,255,0]); put(2,2,[200,150,100]); put(1,1,[0,0,0])
        let art = CursorArt(sprite: Sprite(width:5,height:5,rgba:pixels))
        XCTAssertEqual(art.hotX,2); XCTAssertEqual(art.hotY,3)
        XCTAssertEqual(art.sprite.rgba[(2*5+2)*4+3],255)
        XCTAssertEqual(art.sprite.rgba[(1*5+1)*4+3],0)
        XCTAssertEqual(art.sprite.rgba[2*4+3],0)
    }
    func testInstalledCursorArtwork() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("uo1998-client")
        guard FileManager.default.fileExists(atPath: directory.path) else { throw XCTSkip("Local assets absent") }
        let assets = try ClientAssets(directory: directory)
        var pixels = [UInt8](repeating: 40,count: 256*64*4)
        for p in stride(from:3,to:pixels.count,by:4) { pixels[p] = 255 }
        for (column,id) in [0x2073,0x2072,0x2076,0x205C].enumerated() {
            let cursor = CursorArt(sprite: try XCTUnwrap(assets.sprite(id+0x4000)))
            XCTAssertLessThan(cursor.hotX,cursor.sprite.width); XCTAssertLessThan(cursor.hotY,cursor.sprite.height)
            XCTAssertTrue(cursor.sprite.rgba.enumerated().contains { $0.offset % 4 == 3 && $0.element == 255 })
            for y in 0..<min(64,cursor.sprite.height) {
                for x in 0..<min(64,cursor.sprite.width) {
                    let source = (y*cursor.sprite.width+x)*4, dest = (y*256+column*64+x)*4
                    if cursor.sprite.rgba[source+3] != 0 { pixels.replaceSubrange(dest..<dest+4,with:cursor.sprite.rgba[source..<source+4]) }
                }
            }
        }
        if let path = ProcessInfo.processInfo.environment["UO_CURSOR_PREVIEW"] {
            try Frame(width:256,height:64,rgba:pixels,landCount:0,staticCount:0,missingCount:0,huedCount:0).writeBMP(to:URL(fileURLWithPath:path))
        }
    }
    func testStatePriority() {
        XCTAssertEqual(CursorArt.graphic(war:false,targeting:false,pickup:false),0x2073)
        XCTAssertEqual(CursorArt.graphic(war:true,targeting:false,pickup:false),0x205C)
        XCTAssertEqual(CursorArt.graphic(war:false,targeting:true,pickup:true),0x2076)
        XCTAssertEqual(CursorArt.graphic(war:false,targeting:false,pickup:true),0x2072)
    }
}
