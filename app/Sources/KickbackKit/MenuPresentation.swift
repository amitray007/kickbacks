import Foundation

public enum AuthPhase: Equatable, Sendable { case signedOut, signingIn, signedIn }
public enum MenuTint: String, Equatable, Sendable { case primary, amber, green, red, muted }
public enum MenuBarStyle: String, CaseIterable, Sendable { case today, lifetime, iconOnly }

/// Pure mapping from (auth phase, earning state) to the menu-bar label string and tint.
public enum MenuPresentation {
  public static func menuBarLabel(phase: AuthPhase, todayValue: String, lifetimeValue: String,
                                  style: MenuBarStyle, hideAmounts: Bool) -> String {
    switch phase {
    case .signingIn: return "K$ …"
    case .signedOut: return "K$ —"
    case .signedIn:
      if style == .iconOnly { return "K$" }
      if hideAmounts { return "K$ ••" }
      return "K$ " + (style == .lifetime ? lifetimeValue : todayValue)
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
