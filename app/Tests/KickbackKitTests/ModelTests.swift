import XCTest
@testable import KickbackKit

final class ModelTests: XCTestCase {
  func testDecodesEarningModel() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$0.56 ▴","today":"$0.56","lifetime":"$12.34","rate":"$0.18/hr","trend":"up","cap":"$0.56 / $1.00","capPct":56,"resets":"4h12m","projection":"~2h26m","spark":"▁▂▃","ad":"Inflowpay","adUrl":"https://x.test","status":"Earning","ageSeconds":4,"menuValue":"0.56","viewThresholdSeconds":15,"ads":[{"text":"Inflowpay","url":"https://x.test","icon":"https://cdn.test/i.png"}],"lastEarnedAgoSeconds":120,"collecting":false}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.menuValue, "0.56")
    XCTAssertEqual(m.ads.first?.text, "Inflowpay")
    XCTAssertEqual(m.ads.first?.icon, "https://cdn.test/i.png")
    XCTAssertEqual(m.viewThresholdSeconds, 15)
    XCTAssertFalse(m.collecting)
  }

  func testDecodesSignedOut() throws {
    let json = #"{"signedIn":false,"state":"signed-out","title":"kickback","today":"$0.00","lifetime":"$0.00","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"","adUrl":"","status":"Signed out","ageSeconds":0,"menuValue":"—","viewThresholdSeconds":null,"ads":[],"lastEarnedAgoSeconds":null,"collecting":false}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.state, .signedOut)
    XCTAssertEqual(m.menuValue, "—")
    XCTAssertNil(m.viewThresholdSeconds)
  }

  func testDecodeFailureIsNil() {
    XCTAssertNil(MenuModel.decode(Data("not json".utf8)))
  }
}
