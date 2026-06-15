import Foundation

public enum AuthPhase: Equatable, Sendable { case signedOut, signingIn, signedIn }
public enum MenuTint: String, Equatable, Sendable { case primary, amber, green, red, muted }
public enum MenuBarStyle: String, CaseIterable, Sendable { case today, week, lifetime, rate, iconOnly }

/// Pure mapping from (auth phase, earning state) to the menu-bar label string and tint.
public enum MenuPresentation {
  public static func menuBarLabel(phase: AuthPhase, style: MenuBarStyle, hideAmounts: Bool,
                                  today: String, week: String, lifetime: String, rate: String) -> String {
    switch phase {
    case .signingIn: return "K$ …"
    case .signedOut: return "K$ —"
    case .signedIn:
      if style == .iconOnly { return "K$" }
      if hideAmounts { return "K$ ••" }
      let v: String
      switch style {
      case .today:    v = today
      case .week:     v = week
      case .lifetime: v = lifetime
      case .rate:     v = rate
      case .iconOnly: v = ""
      }
      return v.isEmpty ? "K$ —" : "K$ " + v
    }
  }

  public static func tint(state: MenuState, phase: AuthPhase) -> MenuTint {
    guard phase == .signedIn else { return .muted }
    switch state {
    case .stalled: return .amber
    case .cap:     return .green
    case .killed:  return .red
    case .earning: return .primary
    case .noServe, .signedOut: return .muted
    }
  }
}
