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

  /// Fallback shown on any failure (no binary, spawn/parse error, signed out).
  public static let signedOut = MenuModel(
    signedIn: false, state: .signedOut, title: "kickback",
    today: "$0.00", lifetime: "$0.00", rate: "", trend: "flat", cap: "", capPct: 0,
    resets: "", projection: "", spark: "", ad: "", adUrl: "", status: "Signed out", ageSeconds: 0,
    menuValue: "—", viewThresholdSeconds: nil, ads: [], lastEarnedAgoSeconds: nil, collecting: false)

  public static func decode(_ data: Data) -> MenuModel? {
    try? JSONDecoder().decode(MenuModel.self, from: data)
  }
}
