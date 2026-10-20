import XCTest
@testable import UOCore
final class SmeltWorkflowTests:XCTestCase {
    let position=WalkPoint(x:10,y:10,z:0)
    func item(_ serial:UInt8=4,graphic:Int=0x19B9,amount:UInt8=5)->Data {
        Data([0x25,0x40,0,0,serial,UInt8(graphic>>8),UInt8(graphic&255),0,0,amount,0,0,0,0,0,0,0,2,0,0])
    }
    func setup()throws->(WorldState,SmeltWorkflow) {
        var world=WorldState()
        try world.apply(item()); try world.apply(item(5))
        try world.apply(Data([0x1A,0,14,0x40,0,0,9,0x0F,0xB1,0,11,0,10,0]))
        var flow=SmeltWorkflow()
        try flow.start(backpack:2,forge:world.items[0x40000009]!,world:world,combineOre:false)
        return (world,flow)
    }
    func cursor()throws->TargetRequest { try TargetRequest.decode(Data([0x6C,0,0,0,0,1,0])+Data(repeating:0,count:12)) }
    func say(_ s:String)->SpeechMessage { .init(serial:.max,type:6,name:"",text:s) }
    let success="You smelt the ore removing the impurities and put the metal in your backpack."
    func testSuccessThenInsufficientPileCompletesWithoutRepeating()throws {
        var (world,flow)=try setup()
        XCTAssertEqual(flow.next(world:world,position:position,time:0),.useItem(0x40000004))
        let request=try cursor()
        XCTAssertEqual(flow.receive(request,world:world,position:position,time:0.1),.target(request,.init(serial:0x40000009,x:11,y:10,z:0,graphic:0xFB1)))
        flow.observe(speech:say(success),world:world,time:0.2)
        XCTAssertEqual(flow.state,.working)
        try world.apply(item(6,graphic:0x1BF2))
        XCTAssertNil(flow.next(world:world,position:position,time:0.3))
        XCTAssertEqual(flow.successes,1)
        XCTAssertNil(flow.next(world:world,position:position,time:1))
        XCTAssertEqual(flow.next(world:world,position:position,time:1.4),.useItem(0x40000005))
        _=flow.receive(request,world:world,position:position,time:1.5)
        flow.observe(speech:say("There is not enough metal-bearing ore in this pile to make an ingot."),world:world,time:1.6)
        XCTAssertEqual(flow.state,.completed); XCTAssertEqual(flow.skipped,1)
        XCTAssertNil(flow.next(world:world,position:position,time:10))
    }
    func testConfirmedLossRetriesRemainingOreAfterDelay()throws {
        var (world,flow)=try setup()
        _=flow.next(world:world,position:position,time:0)
        _=flow.receive(try cursor(),world:world,position:position,time:0.1)
        try world.apply(item(amount:2))
        flow.observe(speech:say("You burn away the impurities but are left with less useable metal."),world:world,time:1)
        XCTAssertEqual(flow.state,.coolingDown); XCTAssertEqual(flow.losses,1)
        XCTAssertNil(flow.next(world:world,position:position,time:2))
        XCTAssertEqual(flow.next(world:world,position:position,time:3),.useItem(0x40000004))
    }
    func testSourceAndForgeMustStillMatchAndBeInReach()throws {
        var (world,flow)=try setup()
        try world.apply(item(amount:4))
        XCTAssertNil(flow.next(world:world,position:position,time:0))
        XCTAssertEqual(flow.state,.stopped(.missingTool))
        (world,flow)=try setup()
        XCTAssertNil(flow.next(world:world,position:.init(x:20,y:20,z:0),time:0))
        XCTAssertEqual(flow.state,.stopped(.unreachable))
        (world,flow)=try setup()
        _=flow.next(world:world,position:position,time:0)
        try world.apply(Data([0x1D,0x40,0,0,9]))
        XCTAssertEqual(flow.receive(try cursor(),world:world,position:position,time:1),.cancelTarget(try cursor()))
    }
    func testTimeoutAndStopNeverReplayAndCancelLateCursor()throws {
        var (world,flow)=try setup()
        _=flow.next(world:world,position:position,time:0)
        XCTAssertNil(flow.next(world:world,position:position,time:10))
        XCTAssertEqual(flow.state,.stopped(.timeout))
        XCTAssertEqual(flow.receive(try cursor(),world:world,position:position,time:11),.cancelTarget(try cursor()))
        (world,flow)=try setup()
        _=flow.next(world:world,position:position,time:0); flow.stop()
        XCTAssertEqual(flow.receive(try cursor(),world:world,position:position,time:1),.cancelTarget(try cursor()))
        XCTAssertNil(flow.next(world:world,position:position,time:20))
    }
    func testCombineWaitsForBothInventoryUpdatesInEitherOrder()throws {
        for removalFirst in [false,true] {
            var (world,_)=try setup()
            var flow=SmeltWorkflow()
            try flow.start(backpack:2,forge:world.items[0x40000009]!,world:world)
            XCTAssertEqual(flow.next(world:world,position:position,time:0),.useItem(0x40000004))
            let request=try cursor()
            XCTAssertEqual(flow.receive(request,world:world,position:position,time:0.1),
                .target(request,.init(serial:0x40000005,x:0,y:0,z:0,graphic:0x19B9)))
            let removed=Data([0x1D,0x40,0,0,4]),grown=item(5,amount:10)
            try world.apply(removalFirst ? removed:grown)
            flow.observe(world:world,time:0.2)
            XCTAssertEqual(flow.state,.working)
            try world.apply(removalFirst ? grown:removed)
            flow.observe(world:world,time:0.3)
            XCTAssertEqual(flow.combined,1)
            XCTAssertNil(flow.next(world:world,position:position,time:1))
            XCTAssertEqual(flow.next(world:world,position:position,time:1.4),.useItem(0x40000005))
            XCTAssertFalse(flow.combining)
            XCTAssertEqual(flow.receive(request,world:world,position:position,time:1.5),
                .target(request,.init(serial:0x40000009,x:11,y:10,z:0,graphic:0xFB1)))
        }
    }
    func testDifferentMetalDoesNotCombineAndMissingConfirmationStops()throws {
        var (world,_)=try setup()
        var colored=item(5); colored[colored.count-1]=1; try world.apply(colored)
        var flow=SmeltWorkflow(); try flow.start(backpack:2,forge:world.items[0x40000009]!,world:world)
        _=flow.next(world:world,position:position,time:0)
        XCTAssertFalse(flow.combining)
        (world,_)=try setup()
        flow=SmeltWorkflow(); try flow.start(backpack:2,forge:world.items[0x40000009]!,world:world)
        _=flow.next(world:world,position:position,time:0)
        _=flow.receive(try cursor(),world:world,position:position,time:0.1)
        try world.apply(item(5,amount:10))
        _=flow.next(world:world,position:position,time:11)
        XCTAssertEqual(flow.state,.stopped(.timeout))
        XCTAssertEqual(flow.combined,0)
    }
    func testRepeatedConfirmedLossAdvancesAfterThreeAttempts()throws {
        var (world,flow)=try setup()
        for (attempt,amount) in [4,3,2].enumerated() {
            let time=Double(attempt*4)
            XCTAssertEqual(flow.next(world:world,position:position,time:time),.useItem(0x40000004))
            _=flow.receive(try cursor(),world:world,position:position,time:time+0.1)
            try world.apply(item(amount:UInt8(amount)))
            flow.observe(speech:say("You burn away the impurities but are left with less useable metal."),world:world,time:time+0.2)
        }
        XCTAssertEqual(flow.losses,3); XCTAssertEqual(flow.skipped,1)
        XCTAssertEqual(flow.next(world:world,position:position,time:12),.useItem(0x40000005))
    }

}
