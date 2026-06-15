import XCTest
@testable import KickbacksKit

final class MilestoneAlertTests: XCTestCase {
  func testHighestCrossed() {
    XCTAssertEqual(MilestoneAlert.highestCrossed(0), 0)
    XCTAssertEqual(MilestoneAlert.highestCrossed(9.99), 0)
    XCTAssertEqual(MilestoneAlert.highestCrossed(10), 10)
    XCTAssertEqual(MilestoneAlert.highestCrossed(63), 50)
    XCTAssertEqual(MilestoneAlert.highestCrossed(100), 100)
    XCTAssertEqual(MilestoneAlert.highestCrossed(999), 500)
    XCTAssertEqual(MilestoneAlert.highestCrossed(12_000), 10_000)
  }
}
