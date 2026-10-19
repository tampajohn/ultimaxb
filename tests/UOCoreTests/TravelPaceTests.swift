import XCTest
@testable import UOCore
final class TravelPaceTests:XCTestCase {
    func testReserveAndRecoveryHysteresis() {
        var pace=TravelPace()
        XCTAssertEqual(TravelPace.reserve(maximum:15),4)
        XCTAssertEqual(TravelPace.reserve(maximum:100),10)
        XCTAssertEqual(pace.direction(0x83,stamina:4,maximum:15,enemyDistances:[],at:0),3)
        XCTAssertEqual(pace.mode,.conserving)
        XCTAssertEqual(pace.direction(0x83,stamina:5,maximum:15,enemyDistances:[],at:1),3)
        XCTAssertEqual(pace.direction(0x83,stamina:7,maximum:15,enemyDistances:[],at:2),0x83)
        XCTAssertEqual(pace.mode,.cruising)
    }
    func testThreatSpendsReserveEvenWhenTravelWasWalking() {
        var pace=TravelPace()
        XCTAssertEqual(pace.direction(6,stamina:4,maximum:15,enemyDistances:[7,8],at:0),0x86)
        XCTAssertEqual(pace.mode,.escaping)
        XCTAssertEqual(pace.direction(6,stamina:3,maximum:15,enemyDistances:[],at:2),0x86)
        XCTAssertEqual(pace.direction(6,stamina:3,maximum:15,enemyDistances:[],at:3),6)
        XCTAssertEqual(pace.mode,.conserving)
    }
    func testSingleCloseEnemyButNotOneDistantMonsterTriggersRun() {
        var pace=TravelPace()
        XCTAssertEqual(pace.direction(1,stamina:10,maximum:15,enemyDistances:[7],at:0),1)
        XCTAssertEqual(pace.direction(1,stamina:10,maximum:15,enemyDistances:[4],at:1),0x81)
    }
    func testExhaustionAlwaysOverridesEscapeAndUnknownStatsPreserveControls() {
        var pace=TravelPace()
        for direction in UInt8(0)...7 {
            XCTAssertEqual(pace.direction(direction|0x80,stamina:1,maximum:15,enemyDistances:[1,2],at:0),direction)
        }
        XCTAssertEqual(pace.mode,.exhausted)
        XCTAssertEqual(pace.direction(0x82,stamina:nil,maximum:nil,enemyDistances:[1],at:1),0x82)
        XCTAssertEqual(pace.direction(2,stamina:nil,maximum:nil,enemyDistances:[1],at:1),2)
        XCTAssertEqual(TravelPace.reserve(maximum:2),0)
    }
}
