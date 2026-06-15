import XCTest
@testable import KickbacksKit

final class MenuPresentationTests: XCTestCase {
  func testLabel() {
    func label(_ p: AuthPhase, _ style: MenuBarStyle = .today, hide: Bool = false) -> String {
      MenuPresentation.menuBarLabel(phase: p, style: style, hideAmounts: hide,
                                    today: "12.34", week: "88.00", lifetime: "402.10", rate: "0.18/hr")
    }
    XCTAssertEqual(label(.signedOut), "K$ —")
    XCTAssertEqual(label(.signingIn), "K$ …")
    XCTAssertEqual(label(.signedIn, .today), "K$ 12.34")
    XCTAssertEqual(label(.signedIn, .week), "K$ 88.00")
    XCTAssertEqual(label(.signedIn, .lifetime), "K$ 402.10")
    XCTAssertEqual(label(.signedIn, .rate), "K$ 0.18/hr")
    XCTAssertEqual(label(.signedIn, .iconOnly), "K$")
    XCTAssertEqual(label(.signedIn, .today, hide: true), "K$ ••")
  }

  func testTint() {
    XCTAssertEqual(MenuPresentation.tint(state: .stalled, phase: .signedIn), .amber)
    XCTAssertEqual(MenuPresentation.tint(state: .cap, phase: .signedIn), .green)
    XCTAssertEqual(MenuPresentation.tint(state: .killed, phase: .signedIn), .red)
    XCTAssertEqual(MenuPresentation.tint(state: .earning, phase: .signedIn), .primary)
    XCTAssertEqual(MenuPresentation.tint(state: .earning, phase: .signingIn), .muted)
  }
}
