import Foundation

public struct DayBucket: Codable, Equatable, Sendable {
  public var date: String
  public var usd: Double
  public var hitCap: Bool
}

public struct BestDay: Codable, Equatable, Sendable {
  public var date: String
  public var usd: Double
}

/// Decoded from `kickback history`. Mirrors HistoryJson in cli/src/history.ts.
public struct HistoryModel: Codable, Equatable, Sendable {
  public var thisWeekUsd: Double
  public var thisMonthUsd: Double
  public var bestDay: BestDay?
  public var avgPerDayUsd: Double
  public var daysTracked: Int
  public var lifetimeUsd: Double
  public var sinceInstallUsd: Double
  public var firstSampleTs: Double?
  public var daily: [DayBucket]
  public var capHitsLast7: Int
  public var campaignsSeen: Int
  public var activeHours: Double

  public var isEmpty: Bool { daysTracked == 0 }
  public var hasEnough: Bool { daysTracked >= 2 }

  /// Demo stats for "Demo mode" — randomized per call (new each launch). Cache for the session.
  public static func makeDemo() -> HistoryModel {
    let week = Double.random(in: 60...300)
    let month = week * Double.random(in: 3...4.2)
    let days = Int.random(in: 8...40)
    return HistoryModel(
      thisWeekUsd: week, thisMonthUsd: month, bestDay: BestDay(date: "2026-06-10", usd: Double.random(in: 20...75)),
      avgPerDayUsd: month / Double(min(days, 30)), daysTracked: days,
      lifetimeUsd: month * Double.random(in: 1.5...3), sinceInstallUsd: month,
      firstSampleTs: nil, daily: [], capHitsLast7: Int.random(in: 0...5),
      campaignsSeen: Int.random(in: 10...50), activeHours: Double.random(in: 10...50))
  }

  public static func decode(_ data: Data) -> HistoryModel? {
    try? JSONDecoder().decode(HistoryModel.self, from: data)
  }
}
