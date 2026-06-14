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

  public static func decode(_ data: Data) -> HistoryModel? {
    try? JSONDecoder().decode(HistoryModel.self, from: data)
  }
}
