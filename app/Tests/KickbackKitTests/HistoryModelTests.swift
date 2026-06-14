import XCTest
@testable import KickbackKit

final class HistoryModelTests: XCTestCase {
  func testDecodesFull() throws {
    let json = #"{"thisWeekUsd":16,"thisMonthUsd":20,"bestDay":{"date":"2026-06-28","usd":10},"avgPerDayUsd":6.67,"daysTracked":3,"lifetimeUsd":103,"sinceInstallUsd":3,"firstSampleTs":1781000000000,"daily":[{"date":"2026-06-09","usd":5,"hitCap":true}],"capHitsLast7":1,"campaignsSeen":2,"activeHours":1.5}"#
    let h = try XCTUnwrap(HistoryModel.decode(Data(json.utf8)))
    XCTAssertEqual(h.daysTracked, 3)
    XCTAssertEqual(h.bestDay?.usd, 10)
    XCTAssertEqual(h.daily.first?.hitCap, true)
    XCTAssertTrue(h.hasEnough)
    XCTAssertFalse(h.isEmpty)
  }

  func testDecodesEmpty() throws {
    let json = #"{"thisWeekUsd":0,"thisMonthUsd":0,"bestDay":null,"avgPerDayUsd":0,"daysTracked":0,"lifetimeUsd":0,"sinceInstallUsd":0,"firstSampleTs":null,"daily":[],"capHitsLast7":0,"campaignsSeen":0,"activeHours":0}"#
    let h = try XCTUnwrap(HistoryModel.decode(Data(json.utf8)))
    XCTAssertTrue(h.isEmpty)
    XCTAssertFalse(h.hasEnough)
    XCTAssertNil(h.bestDay)
  }
}
