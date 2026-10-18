import XCTest
@testable import UOCore
final class ControllerStateTests: XCTestCase {
    func testDirectionsAndRun() {
        var state = ControllerState()
        _ = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true)
        for (x,y,direction) in [(1.0,0.0,1),(1,1,0),(0,1,7),(-1,1,6),(-1,0,5),(-1,-1,4),(0,-1,3),(1,-1,2)] {
            XCTAssertEqual(state.sample(x:x,y:y,trigger:0,buttons:[],enabled:true).direction,UInt8(direction))
            XCTAssertEqual(state.sample(x:x,y:y,trigger:1,buttons:[],enabled:true).direction,UInt8(direction)|0x80)
        }
        XCTAssertNil(state.sample(x:0.1,y:0.1,trigger:1,buttons:[],enabled:true).direction)
    }
    func testFocusRequiresNeutralAndButtonsFireOnce() {
        var state = ControllerState()
        XCTAssertNil(state.sample(x:1,y:0,trigger:0,buttons:[.use],enabled:true).direction)
        _ = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true)
        XCTAssertEqual(state.sample(x:0,y:0,trigger:0,buttons:[.use],enabled:true).actions,[.use])
        XCTAssertTrue(state.sample(x:0,y:0,trigger:0,buttons:[.use],enabled:true).actions.isEmpty)
        _ = state.sample(x:1,y:0,trigger:0,buttons:[.use],enabled:false)
        let held = state.sample(x:1,y:0,trigger:0,buttons:[.use],enabled:true)
        XCTAssertNil(held.direction); XCTAssertTrue(held.actions.isEmpty)
        _ = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true)
        XCTAssertEqual(state.sample(x:1,y:0,trigger:0,buttons:[],enabled:true).direction,1)
        state.suspend()
        XCTAssertNil(state.sample(x:1,y:0,trigger:0,buttons:[],enabled:true).direction)
    }
    func testCursorDeadzoneVelocityAndNeutralRearm() {
        var state = ControllerState()
        let initial = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true,cursorX:1)
        XCTAssertEqual(initial.cursorX,0)
        _ = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true)
        let up = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true,cursorY:1)
        XCTAssertEqual(up.cursorX,0); XCTAssertEqual(up.cursorY,-1)
        let diagonal = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true,cursorX:1,cursorY:1)
        XCTAssertEqual(hypot(diagonal.cursorX,diagonal.cursorY),1,accuracy:0.0001)
        let drift = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:true,cursorX:0.1,cursorY:0.1)
        XCTAssertEqual(drift.cursorX,0); XCTAssertEqual(drift.cursorY,0)
        _ = state.sample(x:0,y:0,trigger:0,buttons:[],enabled:false)
        let blocked = state.sample(x:0,y:0,trigger:0,buttons:[.use],enabled:true,cursorX:1)
        XCTAssertEqual(blocked.cursorX,0); XCTAssertTrue(blocked.actions.isEmpty)
    }

}
