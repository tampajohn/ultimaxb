import XCTest
@testable import UOCore
final class SmeltOutcomeTests:XCTestCase {
    func item(_ serial:UInt8=4,graphic:Int=0x19B9,amount:Int=5,bag:UInt32=2)->Data {
        Data([0x25,0x40,0,0,serial,UInt8(graphic>>8),UInt8(graphic&255),0,0,UInt8(amount),0,0,0,0])+Data(LoginPackets.seed(bag))+Data([0,0])
    }
    func speech(_ text:String,serial:UInt32 = .max)->SpeechMessage { .init(serial:serial,type:6,name:"",text:text) }
    let success="You smelt the ore removing the impurities and put the metal in your backpack."
    let loss="You burn away the impurities but are left with less useable metal."
    func testSuccessRequiresMessageAndIngotsInEitherOrder() throws {
        for messageFirst in [true,false] {
            var world=WorldState(); try world.apply(item())
            try world.apply(item(5,graphic:0x1BF2,amount:10))
            var result=try SmeltOutcome(ore:world.containerItems[0x40000004]!,backpack:2,world:world,time:0)
            if messageFirst { XCTAssertNil(result.observe(speech:speech(success),world:world,time:1)) }
            try world.apply(item(5,graphic:0x1BF2,amount:12))
            if !messageFirst { XCTAssertNil(result.observe(world:world,time:1)) }
            XCTAssertEqual(result.observe(speech:messageFirst ? nil:speech(success),world:world,time:2),.success)
            XCTAssertNil(result.observe(speech:speech(success),world:world,time:3))
        }
    }
    func testLossWaitsForSmallerPileOrRemoval() throws {
        for remove in [false,true] {
            var world=WorldState(); try world.apply(item())
            var result=try SmeltOutcome(ore:world.containerItems[0x40000004]!,backpack:2,world:world,time:0)
            XCTAssertNil(result.observe(speech:speech(loss),world:world,time:1))
            try world.apply(remove ? Data([0x1D,0x40,0,0,4]):item(amount:2))
            XCTAssertEqual(result.observe(world:world,time:2),.lostMetal)
        }
    }
    func testUnrelatedChatOrOtherBagCannotConfirm() throws {
        var world=WorldState(); try world.apply(item())
        var result=try SmeltOutcome(ore:world.containerItems[0x40000004]!,backpack:2,world:world,time:0)
        try world.apply(item(5,graphic:0x1BF2,bag:3))
        XCTAssertNil(result.observe(speech:speech(success),world:world,time:1))
        result=try SmeltOutcome(ore:world.containerItems[0x40000004]!,backpack:2,world:world,time:1)
        try world.apply(item(5,graphic:0x1BF2))
        XCTAssertNil(result.observe(speech:speech(success,serial:1),world:world,time:2))
        XCTAssertNil(result.observe(speech:speech(success),world:world,time:11))
    }
    func testForgeGraphicsAndInsufficientOre() throws {
        XCTAssertTrue(SmeltOutcome.isForge(0xFB1)); XCTAssertTrue(SmeltOutcome.isForge(0x197A))
        XCTAssertFalse(SmeltOutcome.isForge(0xFB0)); XCTAssertFalse(SmeltOutcome.isForge(0x19B9))
        var world=WorldState(); try world.apply(item())
        var result=try SmeltOutcome(ore:world.containerItems[0x40000004]!,backpack:2,world:world,time:0)
        XCTAssertEqual(result.observe(speech:speech("There is not enough metal-bearing ore in this pile to make an ingot."),world:world,time:1),.insufficientOre)
    }
    func testLiveSilentConversionInEitherPacketOrder()throws {
        for removalFirst in [false,true] {
            var world=WorldState()
            try world.apply(item(graphic:0x19B7,amount:14))
            try world.apply(item(5,graphic:0x1BF2,amount:29))
            var tracker=try SmeltOutcome(ore:world.containerItems[0x40000004]!,backpack:2,world:world,time:0)
            let removed=Data([0x1D,0x40,0,0,4]),grown=item(5,graphic:0x1BF2,amount:36)
            try world.apply(removalFirst ? removed:grown)
            XCTAssertNil(tracker.observe(world:world,time:1))
            try world.apply(removalFirst ? grown:removed)
            XCTAssertEqual(tracker.observe(world:world,time:2),.success)
            XCTAssertEqual(tracker.diagnostics["inventory_confirmed"],1)
            XCTAssertNil(tracker.observe(world:world,time:3))
        }
    }
    func testSilentSuccessRejectsMovedSourceWrongMetalAndWrongAmount()throws {
        for variant in 0..<3 {
            var world=WorldState(); try world.apply(item(graphic:0x19B7,amount:14))
            var tracker=try SmeltOutcome(ore:world.containerItems[0x40000004]!,backpack:2,world:world,time:0)
            if variant==0 { try world.apply(item(graphic:0x19B7,amount:14,bag:3)) }
            else { try world.apply(Data([0x1D,0x40,0,0,4])) }
            var ingots=item(5,graphic:0x1BF2,amount:variant==2 ? 6:7)
            if variant==1 { ingots[ingots.count-1]=1 }
            try world.apply(ingots)
            XCTAssertNil(tracker.observe(world:world,time:1))
        }
    }

}
