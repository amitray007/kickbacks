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

  /// Fallback shown on any failure (no binary, spawn/parse error, signed out).
  public static let signedOut = MenuModel(
    signedIn: false, state: .signedOut, title: "kickback",
    today: "$0.00", lifetime: "$0.00", rate: "", trend: "flat", cap: "", capPct: 0,
    resets: "", projection: "", spark: "", ad: "", adUrl: "", status: "Signed out", ageSeconds: 0,
    menuValue: "—", viewThresholdSeconds: nil, ads: [], lastEarnedAgoSeconds: nil, collecting: false, recentAds: [])

  /// Believable demo data for the "Fake data" toggle (demos / screenshots). Fictional ads.
  public static let demo = MenuModel(
    signedIn: true, state: .earning, title: "$42.00", today: "$42.00", lifetime: "$1,337.00",
    rate: "$3.50/hr", trend: "up", cap: "$42.00 / $50.00", capPct: 84, resets: "3h20m",
    projection: "~2h", spark: "", ad: "Demo Co — your ad here", adUrl: "https://example.com",
    status: "Earning", ageSeconds: 5, menuValue: "42.00", viewThresholdSeconds: 15,
    ads: [AdItem(text: "Demo Co — your ad here", url: "https://example.com", icon: ""),
          AdItem(text: "Sample Labs — try it free", url: "https://example.com", icon: "")],
    lastEarnedAgoSeconds: 12, collecting: false,
    recentAds: [AdItem(text: "Demo Co — your ad here", url: "https://example.com", icon: ""),
                AdItem(text: "Sample Labs — try it free", url: "https://example.com", icon: ""),
                AdItem(text: "Acme — build something", url: "https://example.com", icon: "")])

  public static func decode(_ data: Data) -> MenuModel? {
    try? JSONDecoder().decode(MenuModel.self, from: data)
  }
}
