import Foundation

/// Mirrors the `state` enum emitted by `kickback model --json`.
public enum MenuState: String, Codable, Sendable {
  case signedOut = "signed-out"
  case killed
  case cap
  case stalled
  case noServe = "no-serve"
  case earning
}

public struct AdItem: Codable, Equatable, Sendable {
  public var text: String
  public var url: String
  public var icon: String
}

/// Display-ready menu model, decoded from `kickback model --json`. The CLI does all
/// the earnings logic; this is the single coupling point between TS and Swift.
public struct MenuModel: Codable, Equatable, Sendable {
  public var signedIn: Bool
  public var state: MenuState
  public var title: String
  public var today: String
  public var lifetime: String
  public var rate: String
  public var trend: String
  public var cap: String
  public var capScope: String?
  public var capPct: Int
  public var resets: String
  public var projection: String
  public var spark: String
  public var ad: String
  public var adUrl: String
  public var status: String
  public var ageSeconds: Int
  public var menuValue: String
  public var viewThresholdSeconds: Int?
  public var ads: [AdItem]
  public var lastEarnedAgoSeconds: Int?
  public var collecting: Bool
  public var recentAds: [AdItem]
  public var todayUsd: Double
  public var hourUsd: Double
  public var lifetimeUsd: Double

  /// Fallback shown on any failure (no binary, spawn/parse error, signed out).
  public static let signedOut = MenuModel(
    signedIn: false, state: .signedOut, title: "kickback",
    today: "$0.00", lifetime: "$0.00", rate: "", trend: "flat", cap: "", capScope: nil, capPct: 0,
    resets: "", projection: "", spark: "", ad: "", adUrl: "", status: "Signed out", ageSeconds: 0,
    menuValue: "—", viewThresholdSeconds: nil, ads: [], lastEarnedAgoSeconds: nil, collecting: false, recentAds: [],
    todayUsd: 0, hourUsd: 0, lifetimeUsd: 0)

  /// Believable demo data for "Demo mode" — randomized per call, so each app launch looks
  /// different. Fictional ads only; amounts stay under the default caps so cap rows read sane.
  /// Cache the result for the session (see MenuVM) rather than calling this on every render.
  public static func makeDemo() -> MenuModel {
    func money(_ v: Double) -> String { "$" + String(format: "%.2f", v) }
    let today = Double.random(in: 4...18)
    let lifetime = Double.random(in: 300...4800)
    let hour = today * Double.random(in: 0.2...0.6)
    let rate = Double.random(in: 1...6)
    let pool = ["Demo Co — your ad here", "Sample Labs — try it free", "Acme — build something",
                "Globex — ship faster", "Initech — automate it", "Hooli — search smarter"].shuffled()
    let recent = pool.prefix(3).map { AdItem(text: $0, url: "https://example.com", icon: "") }
    return MenuModel(
      signedIn: true, state: .earning, title: money(today),
      today: money(today), lifetime: money(lifetime),
      rate: money(rate) + "/hr", trend: Bool.random() ? "up" : "down",
      cap: "", capScope: nil, capPct: 0, resets: "",
      projection: "", spark: "", ad: recent.first?.text ?? "", adUrl: "https://example.com",
      status: "Earning", ageSeconds: Int.random(in: 2...40),
      menuValue: String(format: "%.2f", today), viewThresholdSeconds: 15,
      ads: Array(recent.prefix(2)),
      lastEarnedAgoSeconds: Int.random(in: 3...90), collecting: false,
      recentAds: Array(recent), todayUsd: today, hourUsd: hour, lifetimeUsd: lifetime)
  }

  public static func decode(_ data: Data) -> MenuModel? {
    try? JSONDecoder().decode(MenuModel.self, from: data)
  }
}
