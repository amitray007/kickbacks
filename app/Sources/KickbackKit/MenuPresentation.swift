import Foundation

public enum AuthPhase: Equatable, Sendable { case signedOut, signingIn, signedIn }
public enum MenuTint: String, Equatable, Sendable { case primary, amber, green, red, muted }

/// Pure mapping from (auth phase, earning state) to the menu-bar label string and tint.
public enum MenuPresentation {
  public static func menuBarLabel(phase: AuthPhase, menuValue: String) -> String {
    switch phase {
    case .signingIn: return "K$ …"
    case .signedOut: return "K$ —"
    case .signedIn:  return "K$ \(menuValue)"
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
