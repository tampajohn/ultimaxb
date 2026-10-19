import XCTest
@testable import UOCore
final class OpenObjectWindowsTests:XCTestCase {
    func mobile(_ x:Int)->Data { Data([0x77,0,0,0,1,1,0x90,UInt8(x>>8),UInt8(x&255),0,100,0,0,0,0,0,1]) }
    func equip(_ layer:UInt8)->Data { Data([0x2E,0x40,0,0,1,0x0E,0x75,0,layer,0,0,0,1,0,0]) }
    func nested()->Data { Data([0x25,0x40,0,0,2,0x0E,0xFA,0,0,1,0,10,0,10,0x40,0,0,1,0,0]) }
    func testRemovalClosesNestedBookButEmptyContentsDoNot() throws {
        var world=WorldState(); try world.apply(mobile(100)); try world.apply(equip(21)); try world.apply(nested())
        var windows=OpenObjectWindows(); windows.register(0x40000001,world:world,player:1); windows.register(0x40000002,world:world,player:1)
        try world.apply(Data([0x24,0x40,0,0,2,0xFF,0xFF])); try world.apply(Data([0x3C,0,5,0,0]))
        XCTAssertTrue(windows.reconcile(world:world,player:1).isEmpty)
        XCTAssertEqual(windows.removed(0x40000001),[0x40000001,0x40000002])
    }
    func testBankRangeAndCarriedBooksHaveDifferentLifetimes() throws {
        for layer:UInt8 in [21,29] {
            var world=WorldState(); try world.apply(mobile(100)); try world.apply(equip(layer)); try world.apply(nested())
            var windows=OpenObjectWindows(); windows.register(0x40000002,world:world,player:1)
            try world.apply(mobile(110))
            XCTAssertEqual(windows.reconcile(world:world,player:1),layer == 29 ? [0x40000002] : [])
        }
    }
    func testUnknownRootIsNotADeletionAndDismissStopsTracking() {
        var windows=OpenObjectWindows(); windows.register(7,world:WorldState(),player:1)
        XCTAssertTrue(windows.reconcile(world:WorldState(),player:1).isEmpty)
        windows.dismiss(7); XCTAssertTrue(windows.removed(7).isEmpty)
    }
}
