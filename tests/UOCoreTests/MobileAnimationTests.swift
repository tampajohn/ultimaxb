import XCTest
@testable import UOCore
final class MobileAnimationTests: XCTestCase {
    func testHumanModesAndHands() {
        for body in [400,401] {
            XCTAssertEqual(MobileAnimation.action(body:body,war:false,walking:false,running:false),4)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:false,running:false),7)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:false,running:false,secondHandAnimation:0x263),8)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:false,running:false,firstHand:true,secondHandAnimation:0x263),7)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:false,running:false,secondHandAnimation:0x240),7)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:true,running:false),15)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:true,running:true),2)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:true,running:true,secondHandAnimation:0x263),3)
            XCTAssertEqual(MobileAnimation.action(body:body,war:false,walking:true,running:false,secondHandAnimation:0x263),1)
            XCTAssertEqual(MobileAnimation.action(body:body,war:true,walking:false,running:false,serverAction:11),11)
        }
    }
    func testAnimalAndMonsterGroupsUnchanged() {
        XCTAssertEqual(MobileAnimation.action(body:5,war:true,walking:false,running:false),1)
        XCTAssertEqual(MobileAnimation.action(body:200,war:true,walking:false,running:false),2)
        XCTAssertEqual(MobileAnimation.action(body:200,war:true,walking:true,running:true),1)
    }
}
