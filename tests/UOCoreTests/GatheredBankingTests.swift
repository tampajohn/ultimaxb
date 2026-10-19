import XCTest
@testable import UOCore
final class GatheredBankingTests:XCTestCase {
    let point=WalkPoint(x:2503,y:554,z:0)
    let bank=EquippedItem(serial:3,graphic:0xE7C,layer:29,owner:1)
    func item(_ serial:UInt32=4,amount:Int,bag:UInt32=2)->ContainerItem {
        ContainerItem(serial:serial,graphic:0xF7A,amount:amount,x:0,y:0,container:bag,hue:0)
    }
    func ledger()->GatheredInventory {
        var result=GatheredInventory()
        result.confirm(graphic:0xF7A,hue:0,amount:4,bag:2,before:[item(amount:10)],after:[item(amount:14)])
        return result
    }
    func poll(_ runner:inout GatheredBanking,_ contents:[ContainerItem],time:TimeInterval=1,position:WalkPoint?=nil)->GatheredBanking.Command? {
        runner.next(position:position ?? point,backpack:2,equipment:[bank],contents:contents,gathered:ledger(),time:time)
    }
    func ready()->GatheredBanking {
        var runner=GatheredBanking()
        XCTAssertEqual(runner.begin(player:1,at:point,time:0),.openBank)
        runner.opened(3,equipment:[bank],time:0)
        runner.contentsReceived(for:3)
        return runner
    }
    func testRequiresOwnBankAndFullContents() {
        var runner=GatheredBanking()
        _=runner.begin(player:1,at:point,time:0)
        runner.opened(3,equipment:[EquippedItem(serial:3,graphic:0xE7C,layer:29,owner:99)],time:0)
        runner.contentsReceived(for:3)
        XCTAssertEqual(runner.state,.opening)
        XCTAssertNil(poll(&runner,[item(amount:14)]))
        runner.opened(3,equipment:[bank],time:1)
        runner.contentsReceived(for:99)
        XCTAssertEqual(runner.state,.waitingContents)
        XCTAssertNil(poll(&runner,[item(amount:14)]))
        runner.contentsReceived(for:3)
        XCTAssertEqual(poll(&runner,[item(amount:14)]),.deposit(serial:4,amount:4,bank:3))
    }
    func testMergedDepositPreservesOldGoodsAndWaitsForBothSides() {
        var runner=ready()
        XCTAssertEqual(poll(&runner,[item(amount:14),item(8,amount:20,bag:3)]),.deposit(serial:4,amount:4,bank:3))
        XCTAssertNil(poll(&runner,[item(amount:10),item(8,amount:20,bag:3)],time:2))
        XCTAssertEqual(runner.state,.transferring)
        XCTAssertNil(poll(&runner,[item(amount:10),item(8,amount:24,bag:3)],time:3))
        XCTAssertEqual(runner.state,.ready)
        XCTAssertNil(poll(&runner,[item(amount:10),item(8,amount:24,bag:3)],time:4))
        XCTAssertEqual(runner.state,.complete)
    }
    func testMovementRefusalAndTimeoutStopWithoutMoreCommands() {
        var runner=ready()
        XCTAssertNil(poll(&runner,[item(amount:14)],position:WalkPoint(x:2504,y:554,z:0)))
        guard case .stopped=runner.state else { return XCTFail("Movement must revoke bank access") }
        runner=ready(); _=poll(&runner,[item(amount:14)])
        runner.refuse()
        XCTAssertNil(poll(&runner,[item(amount:14)],time:10))
        guard case .stopped=runner.state else { return XCTFail("Refusal must stop") }
        runner=ready(); _=poll(&runner,[item(amount:14)])
        XCTAssertNil(poll(&runner,[item(amount:10)],time:6))
        guard case .stopped=runner.state else { return XCTFail("A source removal is not a confirmed deposit") }
    }
    func testOpenTimeoutAndBankOwnershipLoss() {
        var runner=GatheredBanking(); _=runner.begin(player:1,at:point,time:0)
        XCTAssertNil(poll(&runner,[],time:5))
        guard case .stopped=runner.state else { return XCTFail("Opening timeout") }
        runner=ready()
        XCTAssertNil(runner.next(position:point,backpack:2,equipment:[],contents:[item(amount:14)],gathered:ledger(),time:1))
        guard case .stopped=runner.state else { return XCTFail("Lost bank identity") }
    }
}
