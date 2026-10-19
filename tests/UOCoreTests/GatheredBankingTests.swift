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
    func testTargetsKnownNestedStackAndConfirmsItsContainer() {
        var runner=ready()
        let pouch=ContainerItem(serial:20,graphic:0xE76,amount:1,x:0,y:0,container:3,hue:0)
        let before=[item(amount:14),pouch,item(21,amount:20,bag:20)]
        XCTAssertEqual(runner.next(position:point,backpack:2,equipment:[bank],contents:before,
            gathered:ledger(),time:1,stackable:{ _ in true }),.deposit(serial:4,amount:4,bank:21))
        XCTAssertNil(poll(&runner,[item(amount:10),pouch,item(21,amount:20,bag:20)],time:2))
        XCTAssertEqual(runner.confirmedTransfers,0)
        XCTAssertNil(poll(&runner,[item(amount:10),pouch,item(21,amount:24,bag:20)],time:3))
        XCTAssertEqual(runner.confirmedTransfers,1)
    }
    func testStackSelectionExcludesUnknownContainersHueAndNonstackables() {
        let wrongHue=ContainerItem(serial:22,graphic:0xF7A,amount:20,x:0,y:0,container:3,hue:1)
        let contents=[item(amount:14),item(21,amount:20,bag:99),wrongHue,item(23,amount:65535,bag:3)]
        var runner=ready()
        XCTAssertEqual(runner.next(position:point,backpack:2,equipment:[bank],contents:contents,
            gathered:ledger(),time:1,stackable:{ _ in true }),.deposit(serial:4,amount:4,bank:3))
        runner=ready()
        XCTAssertEqual(poll(&runner,[item(amount:14),item(8,amount:20,bag:3)]),.deposit(serial:4,amount:4,bank:3))
    }
    func testStackRetryUsesSameTargetAndRemovedBagStops() {
        var runner=ready()
        let pouch=ContainerItem(serial:20,graphic:0xE76,amount:1,x:0,y:0,container:3,hue:0)
        let before=[item(amount:14),pouch,item(21,amount:20,bag:20)]
        _=runner.next(position:point,backpack:2,equipment:[bank],contents:before,gathered:ledger(),time:1,stackable:{ _ in true })
        runner.refuse(reason:255,time:2)
        XCTAssertEqual(poll(&runner,before,time:4),.deposit(serial:4,amount:4,bank:21))
        XCTAssertNil(poll(&runner,[item(amount:14),item(21,amount:20,bag:20)],time:5))
        guard case .stopped=runner.state else { return XCTFail("Unknown bank ancestry must stop transfer") }
    }
    func testTotalsRequireBothSidesAndResetForNextRun() {
        var runner=ready()
        XCTAssertNotNil(poll(&runner,[item(amount:14)]))
        XCTAssertEqual(runner.depositedAmount,0)
        XCTAssertNil(poll(&runner,[item(amount:10)],time:2))
        XCTAssertEqual(runner.confirmedTransfers,0)
        let after=[item(amount:10),item(9,amount:4,bag:3)]
        XCTAssertNil(poll(&runner,after,time:3))
        XCTAssertEqual(runner.depositedAmount,4)
        XCTAssertEqual(runner.confirmedTransfers,1)
        XCTAssertNil(poll(&runner,after,time:4))
        XCTAssertNil(poll(&runner,after,time:5))
        XCTAssertEqual(runner.state,.complete)
        XCTAssertEqual(runner.depositedAmount,4,"Repeated updates must not count the deposit again")
        _=runner.begin(player:1,at:point,time:6)
        XCTAssertEqual(runner.depositedAmount,0)
        XCTAssertEqual(runner.confirmedTransfers,0)
    }
    func testEmptyRunReportsZeroDeposits() {
        var runner=ready()
        XCTAssertNil(poll(&runner,[],time:1))
        XCTAssertEqual(runner.state,.complete)
        XCTAssertEqual(runner.depositedAmount,0)
        XCTAssertEqual(runner.confirmedTransfers,0)
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
    func testBusyRetryIsDelayedBoundedAndRequiresUnchangedInventory() {
        var runner=ready()
        XCTAssertNil(poll(&runner,[item(amount:14)],time:0.5))
        XCTAssertNotNil(poll(&runner,[item(amount:14)],time:1))
        var now:Double=2
        for attempt in 1...3 {
            runner.refuse(reason:255,time:now)
            XCTAssertEqual(runner.state,.retrying)
            XCTAssertEqual(runner.retryCount,attempt)
            XCTAssertNil(poll(&runner,[item(amount:14)],time:now+0.5))
            now += Double(attempt+1)
            XCTAssertEqual(poll(&runner,[item(amount:14)],time:now),.deposit(serial:4,amount:4,bank:3))
        }
        runner.refuse(reason:255,time:now)
        guard case .stopped=runner.state else { return XCTFail("Retry budget must stop") }
        runner=ready(); _=poll(&runner,[item(amount:14)])
        runner.refuse(reason:255,time:2)
        XCTAssertNil(poll(&runner,[item(amount:10)],time:4))
        guard case .stopped=runner.state else { return XCTFail("Changed source cannot be lifted twice") }
    }
    func testConfirmedDepositDuringRetryDoesNotResend() {
        var runner=ready(); _=poll(&runner,[item(amount:14)])
        runner.refuse(reason:255,time:2)
        XCTAssertNil(poll(&runner,[item(amount:10),item(9,amount:4,bag:3)],time:3))
        XCTAssertEqual(runner.state,.ready)
        XCTAssertNil(poll(&runner,[item(amount:10),item(9,amount:4,bag:3)],time:4))
        XCTAssertEqual(runner.state,.complete)
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
