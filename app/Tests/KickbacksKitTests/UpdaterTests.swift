import XCTest
@testable import KickbacksKit

final class UpdaterTests: XCTestCase {
  func testParseVersionVariants() {
    XCTAssertTrue(Updater.parseVersion("v0.2.0")! == (0, 2, 0))
    XCTAssertTrue(Updater.parseVersion("0.10.0")! == (0, 10, 0))
    XCTAssertTrue(Updater.parseVersion("1.2")! == (1, 2, 0))
    XCTAssertTrue(Updater.parseVersion("0.2.0-beta.1")! == (0, 2, 0))
    XCTAssertNil(Updater.parseVersion("garbage"))
    XCTAssertNil(Updater.parseVersion("1.x.3"))
  }

  func testIsNewer() {
    XCTAssertTrue(Updater.isNewer("0.2.0", than: "0.1.0"))
    XCTAssertTrue(Updater.isNewer("v0.2.0", than: "0.1.0"))   // tolerates leading v
    XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.0"))   // numeric, not lexical
    XCTAssertFalse(Updater.isNewer("0.2.0", than: "0.2.0"))   // equal
    XCTAssertFalse(Updater.isNewer("0.1.0", than: "0.2.0"))   // older
    XCTAssertFalse(Updater.isNewer("garbage", than: "0.1.0")) // never a false prompt
  }

  func testParseRelease() {
    let json = ###"{"tag_name":"v0.2.0","body":"## What's new\n- A\n- B","html_url":"https://github.com/amitray007/kickbacks/releases/tag/v0.2.0","published_at":"2026-06-16T08:00:00Z"}"###
    let r = Updater.parseRelease(Data(json.utf8))
    XCTAssertEqual(r?.version, "0.2.0")  // leading v stripped
    XCTAssertEqual(r?.notes, "## What's new\n- A\n- B")
    XCTAssertEqual(r?.htmlURL, "https://github.com/amitray007/kickbacks/releases/tag/v0.2.0")
    XCTAssertEqual(r?.publishedAt, "2026-06-16T08:00:00Z")
    XCTAssertNil(Updater.parseRelease(Data("not json".utf8)))
    XCTAssertNil(Updater.parseRelease(Data(#"{"body":"x"}"#.utf8)))  // no tag_name
  }

  func testClassifyHomebrewBySibling() {
    let m = Updater.classify(
      executablePath: "/opt/homebrew/Cellar/kickbacks/0.2.0/bin/kickbacks-bar",
      cliPath: "/opt/homebrew/bin/kickbacks",
      exists: { $0 == "/opt/homebrew/bin/brew" })
    XCTAssertEqual(m, .homebrew(brewPath: "/opt/homebrew/bin/brew"))
  }

  func testClassifyAppBundle() {
    let m = Updater.classify(
      executablePath: "/Applications/Kickbacks.app/Contents/MacOS/KickbacksBar",
      cliPath: "/Applications/Kickbacks.app/Contents/MacOS/kickbacks",
      exists: { _ in false })
    XCTAssertEqual(m, .appBundle)
  }

  func testClassifyUnknown() {
    let m = Updater.classify(
      executablePath: "/Users/x/dev/.build/release/KickbacksBar",
      cliPath: nil,
      exists: { _ in false })
    XCTAssertEqual(m, .unknown)
  }
}
