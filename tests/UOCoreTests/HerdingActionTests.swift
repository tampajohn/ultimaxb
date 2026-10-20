import XCTest
@testable import UOCore

final class HerdingActionTests:XCTestCase {
    let goal=WalkPoint(x:16,y:20,z:0)
    func animal(x:Int=10,y:Int=20,z:Int=0,serial:UInt32=44)->WorldMobile {
        WorldMobile(serial:serial,body:0xD8,x:x,y:y,z:z)
    }
    func cursor(location:Bool=false,id:UInt32=1,flags:UInt8=0)throws->TargetRequest {
        try TargetRequest.decode(Data([0x6C,location ? 1:0])+Data(LoginPackets.seed(id))+Data([flags])+Data(repeating:0,count:12))
    }
    func message(_ text:String,serial:UInt32 = .max,type:UInt8=6)->SpeechMessage {
        SpeechMessage(serial:serial,type:type,name:"",text:text)
    }
    func ready()throws->HerdingAction {
        var action=HerdingAction()
        XCTAssertEqual(try action.start(tool:0x40000001,animal:animal(),destination:goal,time:0),.useItem(0x40000001))
        _=action.receive(try cursor(),animal:animal(),time:1)
        _=action.receive(try cursor(location:true),animal:animal(),time:2)
        XCTAssertEqual(action.state,.waitingForResult)
        return action
    }
    func testTwoCursorsUseCurrentAnimalAndWaitForActualArrival()throws {
        var action=HerdingAction()
        _=try action.start(tool:0x40000001,animal:animal(),destination:goal,time:0)
        let first=try cursor(),second=try cursor(location:true)
        XCTAssertEqual(action.receive(first,animal:animal(x:11),time:1),
                       .target(first,TargetSelection(serial:44,x:11,y:20,z:0,graphic:0xD8)))
        XCTAssertEqual(action.state,.requestingDestination)
        XCTAssertEqual(action.receive(second,animal:animal(x:11),time:2),
                       .target(second,TargetSelection(x:16,y:20,z:0,graphic:0)))
        action.observe(animal:animal(x:16),ownsTool:true,time:3)
        XCTAssertEqual(action.state,.waitingForResult,"Position alone cannot acknowledge an order")
        action.observe(speech:message("The animal walks where it was instructed to."),animal:animal(x:11),ownsTool:true,time:4)
        XCTAssertEqual(action.state,.followingOrder)
        action.observe(animal:animal(x:16,z:10),ownsTool:true,time:5)
        XCTAssertEqual(action.state,.followingOrder,"Same XY on a different floor is not arrival")
        action.observe(animal:animal(x:16),ownsTool:true,time:6)
        XCTAssertEqual(action.state,.arrived)
    }
    func testFirstTargetRefusalDoesNotWaitForMissingSecondCursor()throws {
        for speech in [
            message("You don't seem to be able to persuade that to move."),
            message("That animal looks tame already.",serial:44,type:0),
            message("Someone else is already taming this.",serial:44,type:0),
            message("That being can not be tamed.",serial:44,type:0)
        ] {
            var action=HerdingAction()
            _=try action.start(tool:9,animal:animal(),destination:goal,time:0)
            _=action.receive(try cursor(),animal:animal(),time:1)
            action.observe(speech:speech,animal:animal(),ownsTool:true,time:2)
            XCTAssertEqual(action.state,.stopped(.refused))
            let late=try cursor(location:true)
            XCTAssertEqual(action.receive(late,animal:animal(),time:3),.cancelTarget(late))
        }
    }
    func testUnrelatedSpeechCannotFinishOrRefuseAction()throws {
        var action=try ready()
        action.observe(speech:message("The animal walks where it was instructed to.",serial:99,type:0),animal:animal(x:16),ownsTool:true,time:3)
        action.observe(speech:message("That animal looks tame already.",serial:99,type:0),animal:animal(),ownsTool:true,time:4)
        action.observe(speech:message("That wasn't even challenging.",serial:44,type:0),animal:animal(),ownsTool:true,time:5)
        XCTAssertEqual(action.state,.waitingForResult)
        action.observe(speech:message("Target can not be seen."),animal:animal(),ownsTool:true,time:6)
        XCTAssertEqual(action.state,.stopped(.refused))
    }
    func testStuckAnimalTimesOutWithoutClaimingArrival()throws {
        var action=try ready()
        action.observe(speech:message("The animal walks where it was instructed to."),animal:animal(),ownsTool:true,time:3)
        action.tick(time:32.9);XCTAssertEqual(action.state,.followingOrder)
        action.tick(time:33);XCTAssertEqual(action.state,.stopped(.timeout))
        action.observe(animal:animal(x:16),ownsTool:true,time:34)
        XCTAssertEqual(action.state,.stopped(.timeout))
    }
    func testCancellationMissingToolAndAnimalLoss()throws {
        for reason in [AssistantAction.StopReason.cancelled,.disconnected] {
            var action=try ready();action.stop(reason)
            action.observe(speech:message("The animal walks where it was instructed to."),animal:animal(x:16),ownsTool:true,time:3)
            XCTAssertEqual(action.state,.stopped(reason))
        }
        var action=try ready()
        action.observe(animal:animal(),ownsTool:false,time:3)
        XCTAssertEqual(action.state,.stopped(.missingTool))
        action=try ready();action.observe(animal:nil,ownsTool:true,time:3)
        XCTAssertEqual(action.state,.stopped(.invalidSelection))
    }
    func testWrongCursorDuplicateTimeoutAndInvalidStart()throws {
        var action=HerdingAction()
        XCTAssertThrowsError(try action.start(tool:9,animal:animal(serial:0),destination:goal,time:0))
        _=try action.start(tool:9,animal:animal(),destination:goal,time:0)
        let wrong=try cursor(location:true)
        XCTAssertEqual(action.receive(wrong,animal:animal(),time:1),.cancelTarget(wrong))
        XCTAssertEqual(action.state,.stopped(.unexpectedTarget))
        XCTAssertThrowsError(try action.start(tool:9,animal:animal(),destination:goal,time:2))
        action=HerdingAction()
        _=try action.start(tool:9,animal:animal(),destination:goal,time:0)
        let first=try cursor()
        _=action.receive(first,animal:animal(),time:1)
        XCTAssertEqual(action.receive(first,animal:animal(),time:2),.cancelTarget(first))
        action=HerdingAction()
        _=try action.start(tool:9,animal:animal(),destination:goal,time:0)
        XCTAssertEqual(action.receive(first,animal:animal(),time:10),.cancelTarget(first))
        XCTAssertEqual(action.state,.stopped(.timeout))
    }
}
