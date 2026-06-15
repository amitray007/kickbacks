import Foundation

/// Pure decision for lifetime-earnings milestone notifications. Thresholds are ascending;
/// `highestCrossed` returns the largest one ≤ the current lifetime (0 if none reached yet).
/// The caller persists the last-notified level and fires only when it increases.
public enum MilestoneAlert {
  public static let thresholds: [Double] = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]

  public static func highestCrossed(_ lifetimeUsd: Double) -> Double {
    thresholds.last(where: { $0 <= lifetimeUsd }) ?? 0
  }
}
