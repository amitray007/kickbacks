import XCTest
@testable import KickbackKit

final class MenuPresentationTests: XCTestCase {
  func testLabel() {
    XCTAssertEqual(MenuPresentation.menuBarLabel(phase: .signedOut, menuValue: "—"), "K$ —")
    XCTAssertEqual(MenuPresentation.menuBarLabel(phase: .signingIn, menuValue: "1.20"), "K$ …")
    XCTAssertEqual(MenuPresentation.menuBarLabel(phase: .signedIn, menuValue: "12.34"), "K$ 12.34")
  }

  func testTint() {
    XCTAssertEqual(MenuPresentation.tint(state: .stalled, phase: .signedIn), .amber)
    XCTAssertEqual(MenuPresentation.tint(state: .cap, phase: .signedIn), .green)
    XCTAssertEqual(MenuPresentation.tint(state: .killed, phase: .signedIn), .red)
    XCTAssertEqual(MenuPresentation.tint(state: .earning, phase: .signedIn), .primary)
    XCTAssertEqual(MenuPresentation.tint(state: .earning, phase: .signingIn), .muted)
  }
}
