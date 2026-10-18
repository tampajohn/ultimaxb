import XCTest
@testable import UOCore
final class AssistantActionTests:XCTestCase {
    let ground = TargetSelection(x:2562,y:500,z:0,graphic:0)
    func cursor(_ id:UInt32 = 1,location:Bool = true,flags:UInt8 = 0)throws->TargetRequest {
        try TargetRequest.decode(Data([0x6C,location ? 1 : 0]+LoginPackets.seed(id)+[flags]+Array(repeating:0,count:12)))
    }
    func testMiningWaitsForCursorAndResult() throws {
        var action = AssistantAction()
        XCTAssertEqual(try action.start(tool:22,targets:[ground],at:0),.useItem(22))
        action.receive(.success,at:1); XCTAssertEqual(action.state,.waitingForTarget(0))
        let request = try cursor()
        XCTAssertEqual(action.receive(request,at:2),.target(request,ground))
        action.tick(at:3); XCTAssertEqual(action.state,.waitingForResult)
        action.receive(.success,at:4); XCTAssertEqual(action.state,.completed)
        XCTAssertNil(action.receive(try cursor(2),at:5))
        XCTAssertThrowsError(try action.start(tool:22,targets:[ground],at:6))
    }
    func testTwoTargetHerdingSequence() throws {
        var action = AssistantAction()
        let animal = TargetSelection(serial:44,x:2561,y:501,z:0,graphic:225)
        _ = try action.start(tool:23,targets:[animal,ground],at:0)
        let first = try cursor(location:false),second = try cursor(1)
        XCTAssertEqual(action.receive(first,at:1),.target(first,animal))
        XCTAssertEqual(action.state,.waitingForTarget(1))
        XCTAssertEqual(action.receive(second,at:2),.target(second,ground))
        action.receive(.refused,at:3); XCTAssertEqual(action.state,.stopped(.refused))
    }
    func testTimeoutAndManualStopCancelLateCursorWithoutTargeting() throws {
        for reason in [AssistantAction.StopReason.cancelled,.disconnected,.overweight,.missingTool] {
            var action = AssistantAction()
            _ = try action.start(tool:22,targets:[ground],at:0)
            action.stop(reason)
            let request = try cursor()
            XCTAssertEqual(action.receive(request,at:1),.cancelTarget(request))
            XCTAssertEqual(action.state,.stopped(reason))
        }
        var action = AssistantAction()
        _ = try action.start(tool:22,targets:[ground],at:0,timeout:2)
        let request = try cursor()
        XCTAssertEqual(action.receive(request,at:2),.cancelTarget(request))
        XCTAssertEqual(action.state,.stopped(.timeout))
        action.receive(.success,at:3); XCTAssertEqual(action.state,.stopped(.timeout))
    }
    func testIncompatibleDuplicateAndServerCancelledTargets() throws {
        var action = AssistantAction()
        _ = try action.start(tool:22,targets:[ground],at:0)
        let object = try cursor(location:false)
        XCTAssertEqual(action.receive(object,at:1),.cancelTarget(object))
        XCTAssertEqual(action.state,.stopped(.invalidSelection))
        action = AssistantAction(); _ = try action.start(tool:22,targets:[ground,ground],at:0)
        let request = try cursor()
        _ = action.receive(request,at:1)
        XCTAssertEqual(action.receive(request,at:2),.cancelTarget(request))
        XCTAssertEqual(action.state,.stopped(.unexpectedTarget))
        action = AssistantAction(); _ = try action.start(tool:22,targets:[ground],at:0)
        XCTAssertNil(action.receive(try cursor(flags:3),at:1))
        XCTAssertEqual(action.state,.stopped(.serverCancelled))
    }
    func testResultTimeoutAndDepletion() throws {
        var action = AssistantAction()
        _ = try action.start(tool:22,targets:[ground],at:0,timeout:2)
        _ = action.receive(try cursor(),at:1)
        action.receive(.success,at:3)
        XCTAssertEqual(action.state,.stopped(.timeout))
        action = AssistantAction(); _ = try action.start(tool:22,targets:[ground],at:0)
        _ = action.receive(try cursor(),at:1); action.receive(.depleted,at:2)
        XCTAssertEqual(action.state,.stopped(.depleted))
    }
}
