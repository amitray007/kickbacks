import XCTest
@testable import KickbackKit

final class StateAlertTests: XCTestCase {
  func testFiresOnEnteringTroubleStates() {
    XCTAssertEqual(StateAlert.note(for: .stalled, previous: .earning)?.title, "Earnings stalled")
    XCTAssertEqual(StateAlert.note(for: .cap, previous: .earning)?.title, "Daily cap reached")
    XCTAssertEqual(StateAlert.note(for: .killed, previous: .earning)?.title, "Not earning")
  }

  func testNoFireWhenUnchanged() {
    XCTAssertNil(StateAlert.note(for: .stalled, previous: .stalled))
    XCTAssertNil(StateAlert.note(for: .earning, previous: .earning))
  }

  func testRecoveryOnlyFromFailureStates() {
    XCTAssertEqual(StateAlert.note(for: .earning, previous: .stalled)?.title, "Earning again")
    XCTAssertEqual(StateAlert.note(for: .earning, previous: .killed)?.title, "Earning again")
    XCTAssertNil(StateAlert.note(for: .earning, previous: .cap))      // hitting cap isn't a failure
    XCTAssertNil(StateAlert.note(for: .earning, previous: .noServe))
  }

  func testIdleAndSignedOutNeverNotify() {
    XCTAssertNil(StateAlert.note(for: .noServe, previous: .earning))
    XCTAssertNil(StateAlert.note(for: .signedOut, previous: .earning))
  }
}
