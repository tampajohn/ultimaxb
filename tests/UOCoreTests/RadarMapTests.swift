import XCTest
@testable import UOCore
final class RadarMapTests:XCTestCase {
    func testOriginalWidgetMaskPreservesFrameAndTransparency() throws {
        let frame = Sprite(width:2,height:2,rgba:[8,8,8,255, 255,0,0,255, 0,0,0,0, 8,8,8,255])
        let terrain = Sprite(width:4,height:4,rgba:Array(repeating:[UInt8(0),255,0,255],count:16).flatMap { $0 })
        let result = try RadarWidget.compose(frame:frame,terrain:terrain,centerX:2,centerY:2)
        XCTAssertEqual(result.rgba,[0,255,0,255, 255,0,0,255, 0,0,0,0, 0,255,0,255])
    }
    func testPaletteStaticsAndMapEdges() throws {
        var map = Data(repeating:0,count:196)
        for i in 0..<64 { map[4+i*3] = 2 }
        var colors = Data(repeating:0,count:0x10000)
        colors[5] = 124 // land 2: red
        colors[(0x4000+3)*2] = 224; colors[(0x4000+3)*2+1] = 3 // static 3: green
        let index = Data([0,0,0,0,7,0,0,0,0,0,0,0])
        let statics = Data([3,0,1,2,5,0,0])
        let radar = try RadarMap(map:map,staticIndex:index,statics:statics,colors:colors,width:8,height:8)
        let local = try radar.render(x:0,y:0,pixelWidth:8,pixelHeight:8,step:1)
        XCTAssertEqual(Array(local.rgba[0..<4]),[255,0,0,255])
        XCTAssertEqual(Array(local.rgba[68..<72]),[0,255,0,255])
        let edge = try radar.render(x:-1,y:-1,pixelWidth:2,pixelHeight:2,step:1)
        XCTAssertEqual(Array(edge.rgba[0..<4]),[0,0,0,255])
        XCTAssertEqual(Array(edge.rgba[12..<16]),[255,0,0,255])
        let overview = try radar.render(x:0,y:0,pixelWidth:4,pixelHeight:4,step:2)
        XCTAssertEqual(overview.rgba.count,64)
        XCTAssertThrowsError(try radar.render(x:0,y:0,pixelWidth:100000,pixelHeight:2,step:1))
        XCTAssertThrowsError(try radar.render(x:0,y:0,pixelWidth:2,pixelHeight:2,step:0))
        XCTAssertThrowsError(try RadarMap(map:map.dropLast(),staticIndex:index,statics:statics,colors:colors,width:8,height:8))
    }
}
