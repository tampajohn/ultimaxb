import XCTest
@testable import UOCore
final class HarvestWorkflowTests:XCTestCase {
    let position=WalkPoint(x:10,y:10,z:0)
    func site(_ x:Int=10)->HarvestWorkflow.Site { .init(target:.init(x:x,y:11,z:20,graphic:0),standing:.init(x:x,y:10,z:0)) }
    func cursor()->TargetRequest { try! TargetRequest.decode(Data([0x6C,1,0,0,0,1,0])+Data(repeating:0,count:12)) }
    func runner(_ sites:[HarvestWorkflow.Site]?=nil,limit:Int=2)throws->HarvestWorkflow {
        var w=HarvestWorkflow()
        try w.start(zone:.init(x1:10,y1:10,x2:12,y2:12),sites:sites ?? [site()],tool:22,successfulActions:limit)
        return w
    }
    func next(_ w:inout HarvestWorkflow,_ time:Double,position:WalkPoint?=nil,owns:Bool=true,heavy:Bool=false)->HarvestWorkflow.Command? {
        w.next(position:position ?? self.position,ownsTool:owns,overweight:heavy,time:time,route:{_,end in [end]})
    }
    func testHarvestWaitsForResultAndCooldownBeforeRepeating()throws {
        var w=try runner()
        XCTAssertEqual(next(&w,0),.tool(.useItem(22)))
        w.receive(.success,time:0.1); XCTAssertEqual(w.successfulActions,0)
        let request=cursor()
        XCTAssertEqual(w.receive(request,time:1),.tool(.target(request,site().target)))
        XCTAssertNil(next(&w,2)); XCTAssertEqual(w.state,.working)
        w.receive(.success,time:3); XCTAssertEqual(w.successfulActions,1)
        XCTAssertNil(next(&w,3.9))
        XCTAssertEqual(next(&w,4),.tool(.useItem(22)))
        _=w.receive(request,time:5); w.receive(.success,time:6)
        XCTAssertEqual(w.state,.completed); XCTAssertEqual(w.successfulActions,2)
        XCTAssertNil(next(&w,100))
    }
    func testDepletionAdvancesThenWaitsForAuthoritativeArrival()throws {
        var w=try runner([site(),site(11)])
        _=next(&w,0); _=w.receive(cursor(),time:1); w.receive(.depleted,time:2)
        XCTAssertEqual(w.successfulActions,0)
        XCTAssertEqual(next(&w,3),.route([site(11).standing]))
        XCTAssertNil(next(&w,4)); XCTAssertEqual(w.state,.travelling)
        XCTAssertEqual(next(&w,5,position:site(11).standing),.tool(.useItem(22)))
        _=w.receive(cursor(),time:6); w.receive(.depleted,time:7)
        XCTAssertEqual(w.state,.completed)
    }
    func testZoneRejectsRouteThatLeavesAndReenters()throws {
        var w=try runner([site(11)])
        let command=w.next(position:position,ownsTool:true,overweight:false,time:0,route:{_,end in [.init(x:9,y:10,z:0),end]})
        XCTAssertNil(command); XCTAssertEqual(w.state,.stopped(.unreachable))
        w=try runner([site(12)])
        XCTAssertNil(next(&w,0)); XCTAssertEqual(w.state,.stopped(.unreachable),"A two-tile shortcut must not pass route validation")
    }
    func testSkipsUnreachableSiteAndPausesAfterArrival()throws {
        var w=try runner([site(12),site(11)])
        XCTAssertEqual(next(&w,0),.route([site(11).standing]))
        w.pause()
        XCTAssertNil(next(&w,1,position:site(11).standing))
        XCTAssertEqual(w.state,.paused)
        w.resume()
        XCTAssertEqual(next(&w,2,position:site(11).standing),.tool(.useItem(22)))
    }
    func testToolLossWeightAndDisconnectStopWithoutLateTargeting()throws {
        for reason in [AssistantAction.StopReason.missingTool,.overweight,.disconnected] {
            var w=try runner(); _=next(&w,0)
            if reason == .disconnected { w.stop(reason) }
            else { _=next(&w,1,owns:reason != .missingTool,heavy:reason == .overweight) }
            XCTAssertEqual(w.state,.stopped(reason))
            XCTAssertEqual(w.receive(cursor(),time:2),.tool(.cancelTarget(cursor())))
            w.receive(.success,time:3); XCTAssertEqual(w.successfulActions,0)
        }
    }
    func testPauseDrainsActionAndResumeRespectsCooldown()throws {
        var w=try runner(); _=next(&w,0); w.pause()
        _=w.receive(cursor(),time:1); w.receive(.success,time:2)
        XCTAssertEqual(w.state,.paused); XCTAssertNil(next(&w,100))
        w.resume(); XCTAssertNil(next(&w,2.5)); XCTAssertEqual(next(&w,3),.tool(.useItem(22)))
        w.stop(); XCTAssertEqual(w.state,.stopped(.cancelled))
    }
    func testTimeoutAndRefusalNeverRepeat()throws {
        var w=try runner(); _=next(&w,0); _=next(&w,10)
        XCTAssertEqual(w.state,.stopped(.timeout))
        w=try runner(); _=next(&w,0); _=w.receive(cursor(),time:1); w.receive(.refused,time:2)
        XCTAssertEqual(w.state,.stopped(.refused)); XCTAssertNil(next(&w,100))
        w=try runner([site(11)]); _=next(&w,0); _=next(&w,11)
        XCTAssertEqual(w.state,.stopped(.timeout))
    }
    func testEmptyAttemptsRetryWithCooldownButStopAtBound()throws {
        var w=try runner()
        for attempt in 0..<5 {
            let time=Double(attempt*3)
            XCTAssertEqual(next(&w,time),.tool(.useItem(22)))
            _=w.receive(cursor(),time:time+0.5)
            w.receive(.noYield,time:time+1)
            XCTAssertEqual(w.successfulActions,0)
            XCTAssertNil(next(&w,time+1.5))
        }
        XCTAssertEqual(w.state,.stopped(.noProgress))
        XCTAssertNil(next(&w,100))
    }
    func testInvalidConfigurationAndLeavingZone()throws {
        XCTAssertThrowsError(try HarvestWorkflow.Zone(x1:0,y1:0,x2:200,y2:0))
        XCTAssertThrowsError(try runner([site(14)]))
        XCTAssertThrowsError(try runner(limit:0))
        var w=try runner(); XCTAssertNil(next(&w,0,position:.init(x:9,y:10,z:0)))
        XCTAssertEqual(w.state,.stopped(.invalidSelection))
    }
}
