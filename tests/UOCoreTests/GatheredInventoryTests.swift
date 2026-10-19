import XCTest
@testable import UOCore

final class GatheredInventoryTests:XCTestCase {
    private func item(_ amount:Int,graphic:Int=0xF7A,bag:UInt32=2,hue:Int=0)->ContainerItem {
        item(1,amount,graphic:graphic,bag:bag,hue:hue)
    }
    private func item(_ serial:UInt32,_ amount:Int,graphic:Int=0xF7A,bag:UInt32=2,hue:Int=0)->ContainerItem {
        ContainerItem(serial:serial,graphic:graphic,amount:amount,x:0,y:0,container:bag,hue:hue)
    }
    func testMergedGoodsProtectOriginalQuantityAndUnrelatedAdditions() {
        var ledger=GatheredInventory()
        ledger.confirm(graphic:0xF7A,hue:0,amount:2,bag:2,before:[item(10)],after:[item(12)])
        XCTAssertEqual(ledger.transferable(in:2,includeGold:false).map(\.amount),[2])
        ledger.reconcile([item(20)])
        XCTAssertEqual(ledger.credits[1]?.amount,2)
        ledger.reconcile([item(19)])
        XCTAssertEqual(ledger.credits[1]?.amount,1)
        ledger.reconcile([item(18)])
        XCTAssertTrue(ledger.credits.isEmpty)
    }
    func testCreditLimitedToRequestedAmountAndActualIncrease() {
        var ledger=GatheredInventory()
        ledger.confirm(graphic:0xF7A,hue:0,amount:2,bag:2,before:[item(10)],after:[item(100),item(3,20)])
        XCTAssertEqual(ledger.credits.values.reduce(0) { $0+$1.amount },2)
        ledger.confirm(graphic:0xF7A,hue:0,amount:10,bag:2,before:[item(100),item(3,20)],after:[item(101),item(3,20)])
        XCTAssertEqual(ledger.credits.values.reduce(0) { $0+$1.amount },3)
    }
    func testGoldPreservedForOverloadButAvailableForBanking() {
        var ledger=GatheredInventory()
        for (i,graphic) in [0xEED,0xEEE,0xEEF].enumerated() {
            let contents=(0...i).map { item(UInt32($0+1),10,graphic:0xEED+$0) }
            ledger.confirm(graphic:graphic,hue:0,amount:10,bag:2,before:Array(contents.dropLast()),after:contents)
        }
        XCTAssertTrue(ledger.transferable(in:2,includeGold:false).isEmpty)
        XCTAssertEqual(ledger.transferable(in:2,includeGold:true).count,3)
        XCTAssertTrue(ledger.transferable(in:99,includeGold:true).isEmpty)
    }
    func testMovingReplacingOrManuallyUsingStackRelinquishesCredit() {
        for replacement in [[],[item(2,10)],[item(10,bag:3)],[item(10,hue:7)],[item(10,graphic:0xF88)]] {
            var ledger=GatheredInventory()
            ledger.confirm(graphic:0xF7A,hue:0,amount:10,bag:2,before:[],after:[item(10)])
            ledger.reconcile(replacement)
            XCTAssertTrue(ledger.credits.isEmpty)
        }
        var ledger=GatheredInventory()
        ledger.confirm(graphic:0xF7A,hue:0,amount:10,bag:2,before:[],after:[item(10)])
        ledger.relinquish(1)
        XCTAssertTrue(ledger.credits.isEmpty)
    }
}
