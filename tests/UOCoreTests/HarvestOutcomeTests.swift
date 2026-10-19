import XCTest
@testable import UOCore
final class HarvestOutcomeTests:XCTestCase {
    let feet=WalkPoint(x:10,y:10,z:0)
    func speech(_ text:String,serial:UInt32 = .max,type:UInt8=6)->SpeechMessage { .init(serial:serial,type:type,name:"",text:text) }
    func item(_ graphic:Int=0x19B9,amount:Int=1,bag:UInt32=2)->Data {
        Data([0x25,0x40,0,0,4,UInt8(graphic>>8),UInt8(graphic&255),0,0,UInt8(amount),0,0,0,0])+Data(LoginPackets.seed(bag))+Data([0,0])
    }
    let oreMessage="You dig some ore and put it in your backpack."
    func testSuccessNeedsBothMessageAndResourceIncreaseInEitherOrder()throws {
        for messageFirst in [true,false] {
            var world=WorldState(); try world.apply(item(amount:5))
            var outcome=HarvestOutcome(kind:.mining,backpack:2,position:feet,world:world,time:0)
            if messageFirst { XCTAssertNil(outcome.observe(speech:speech(oreMessage),world:world,time:1)) }
            try world.apply(item(amount:6))
            if !messageFirst { XCTAssertNil(outcome.observe(world:world,time:1)) }
            XCTAssertEqual(outcome.observe(speech:messageFirst ? nil : speech(oreMessage),world:world,time:2),.success)
            XCTAssertNil(outcome.observe(speech:speech(oreMessage),world:world,time:3))
        }
    }
    func testOrdinaryChatAndWrongResourceCannotConfirm()throws {
        var world=WorldState()
        var outcome=HarvestOutcome(kind:.mining,backpack:2,position:feet,world:world,time:0)
        try world.apply(item())
        XCTAssertNil(outcome.observe(speech:speech(oreMessage,serial:1),world:world,time:1))
        XCTAssertNil(outcome.observe(speech:speech(oreMessage,type:0),world:world,time:2))
        world=WorldState(); try world.apply(item(0x1BDD))
        XCTAssertNil(outcome.observe(speech:speech(oreMessage),world:world,time:3))
        world=WorldState(); try world.apply(item(bag:3))
        XCTAssertNil(outcome.observe(world:world,time:4))
    }
    func testGroundYieldRequiresThePlayerTileAndGroundMessage()throws {
        var world=WorldState()
        var outcome=HarvestOutcome(kind:.mining,backpack:2,position:feet,world:world,time:0)
        let ground=Data([0x1A,0,14,0x40,0,0,4,0x19,0xB9,0,11,0,10,0])
        try world.apply(ground)
        XCTAssertNil(outcome.observe(speech:speech("You dig some ore and put it at your feet."),world:world,time:1))
        var placed=ground; placed[10]=10; try world.apply(placed)
        XCTAssertEqual(outcome.observe(world:world,time:2),.success)
    }
    func testLumberYieldAndTerminalOutcomes()throws {
        var world=WorldState()
        var outcome=HarvestOutcome(kind:.lumberjacking,backpack:2,position:feet,world:world,time:0)
        try world.apply(item(0x1BDD,amount:10))
        XCTAssertEqual(outcome.observe(speech:speech("You put some logs in your backpack."),world:world,time:1),.success)
        let cases:[(HarvestOutcome.Kind,String,AssistantAction.Result)]=[
            (.mining,"You loosen some rocks but fail to find any useable ore.",.noYield),
            (.lumberjacking,"You hack at the tree for a while, but fail to produce any useable wood.",.noYield),
            (.mining,"There is no metal here to mine.",.depleted),
            (.mining,"Someone has gotten to the metal before you.",.depleted),
            (.lumberjacking,"There's not enough wood here to harvest.",.depleted),
            (.mining,"You can't mine that.",.refused)]
        for (kind,text,result) in cases {
            outcome=HarvestOutcome(kind:kind,backpack:2,position:feet,world:world,time:0)
            XCTAssertEqual(outcome.observe(speech:speech(text),world:world,time:1),result)
            XCTAssertNil(outcome.observe(speech:speech(text),world:world,time:2))
        }
    }
    func testTimeoutAndMissingCurrentInventoryDoNotReportSuccess()throws {
        var world=WorldState()
        var outcome=HarvestOutcome(kind:.mining,backpack:2,position:feet,world:world,time:0)
        try world.apply(item())
        XCTAssertNil(outcome.observe(world:world,time:1))
        world=WorldState()
        XCTAssertNil(outcome.observe(speech:speech(oreMessage),world:world,time:2))
        try world.apply(item())
        XCTAssertNil(outcome.observe(world:world,time:10))
        XCTAssertNil(outcome.observe(world:world,time:11))
    }
}
