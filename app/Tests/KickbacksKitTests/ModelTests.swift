import XCTest
@testable import KickbacksKit

final class ModelTests: XCTestCase {
  func testDecodesEarningModel() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$0.56 ▴","today":"$0.56","lifetime":"$12.34","rate":"$0.18/hr","trend":"up","cap":"$0.56 / $1.00","capPct":56,"resets":"4h12m","projection":"~2h26m","spark":"▁▂▃","ad":"Inflowpay","adUrl":"https://x.test","status":"Earning","ageSeconds":4,"menuValue":"0.56","viewThresholdSeconds":15,"ads":[{"text":"Inflowpay","url":"https://x.test","icon":"https://cdn.test/i.png"}],"lastEarnedAgoSeconds":120,"collecting":false,"recentAds":[{"text":"Inflowpay","url":"https://x.test","icon":"https://cdn.test/i.png"}],"todayUsd":0.56,"hourUsd":0.12,"lifetimeUsd":12.34}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.menuValue, "0.56")
    XCTAssertEqual(m.ads.first?.text, "Inflowpay")
    XCTAssertEqual(m.ads.first?.icon, "https://cdn.test/i.png")
    XCTAssertEqual(m.viewThresholdSeconds, 15)
    XCTAssertFalse(m.collecting)
    XCTAssertEqual(m.recentAds.first?.text, "Inflowpay")
    XCTAssertEqual(m.todayUsd, 0.56)
    XCTAssertEqual(m.hourUsd, 0.12)
    XCTAssertEqual(m.lifetimeUsd, 12.34)
  }

  func testDecodesSignedOut() throws {
    let json = #"{"signedIn":false,"state":"signed-out","title":"kickbacks","today":"$0.00","lifetime":"$0.00","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"","adUrl":"","status":"Signed out","ageSeconds":0,"menuValue":"—","viewThresholdSeconds":null,"ads":[],"lastEarnedAgoSeconds":null,"collecting":false,"recentAds":[],"todayUsd":0,"hourUsd":0,"lifetimeUsd":0}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.state, .signedOut)
    XCTAssertEqual(m.menuValue, "—")
    XCTAssertNil(m.viewThresholdSeconds)
  }

  func testDecodeFailureIsNil() {
    XCTAssertNil(MenuModel.decode(Data("not json".utf8)))
  }

  // Version-skew guard: an older CLI that predates `liveAdActive` must still decode.
  func testDecodesWithoutLiveAdActiveField() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$1 ▴","today":"$1","lifetime":"$2","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"A","adUrl":"https://x.test","status":"Earning","ageSeconds":1,"menuValue":"1","viewThresholdSeconds":null,"ads":[],"lastEarnedAgoSeconds":null,"collecting":false,"recentAds":[],"todayUsd":1,"hourUsd":0,"lifetimeUsd":2}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertNil(m.liveAdActive)
  }

  func testDecodesLiveAdActiveWhenPresent() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$1 ▴","today":"$1","lifetime":"$2","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"A","adUrl":"https://x.test","status":"Earning","ageSeconds":1,"menuValue":"1","viewThresholdSeconds":null,"ads":[],"lastEarnedAgoSeconds":null,"collecting":false,"recentAds":[],"todayUsd":1,"hourUsd":0,"lifetimeUsd":2,"liveAdActive":true}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.liveAdActive, true)
  }

  // Version-skew guard: an older CLI that predates `active` must still decode (defaults to nil).
  func testDecodesWithoutActiveField() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$1 ▴","today":"$1","lifetime":"$2","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"A","adUrl":"https://x.test","status":"Earning","ageSeconds":1,"menuValue":"1","viewThresholdSeconds":null,"ads":[],"lastEarnedAgoSeconds":null,"collecting":false,"recentAds":[],"todayUsd":1,"hourUsd":0,"lifetimeUsd":2}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertNil(m.active)
  }

  func testDecodesActiveFieldWhenPresent() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$1 ▴","today":"$1","lifetime":"$2","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"A","adUrl":"https://x.test","status":"Earning","ageSeconds":1,"menuValue":"1","viewThresholdSeconds":null,"ads":[],"lastEarnedAgoSeconds":null,"collecting":false,"recentAds":[],"todayUsd":1,"hourUsd":0,"lifetimeUsd":2,"active":false}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.active, false)
  }
}
