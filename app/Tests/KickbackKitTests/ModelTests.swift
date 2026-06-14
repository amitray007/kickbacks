import XCTest
@testable import KickbackKit

final class ModelTests: XCTestCase {
  func testDecodesEarningModel() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$0.56 ▴","today":"$0.56","lifetime":"$12.34","rate":"$0.18/hr","trend":"up","cap":"$0.56 / $1.00","capPct":56,"resets":"4h12m","projection":"~2h26m","spark":"▁▂▃","ad":"Inflowpay","adUrl":"https://x.test","status":"Earning","ageSeconds":4}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertTrue(m.signedIn)
    XCTAssertEqual(m.state, .earning)
    XCTAssertEqual(m.today, "$0.56")
    XCTAssertEqual(m.capPct, 56)
    XCTAssertEqual(m.ad, "Inflowpay")
  }

  // The exact JSON the CLI emits when signed out (verified against `kickback model`).
  func testDecodesSignedOut() throws {
    let json = #"{"signedIn":false,"state":"signed-out","title":"kickback","today":"$0.00","lifetime":"$0.00","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"","adUrl":"","status":"Signed out","ageSeconds":0}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.state, .signedOut)
    XCTAssertEqual(m.title, "kickback")
  }

  func testDecodeFailureIsNil() {
    XCTAssertNil(MenuModel.decode(Data("not json".utf8)))
  }
}
