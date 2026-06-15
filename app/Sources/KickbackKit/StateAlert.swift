import Foundation

/// Pure, edge-triggered decision: given a state transition, what (if anything) to
/// notify the user about. Fires only on a real change — entering a trouble state
/// (stalled / cap / killed) or recovering to earning from a failure.
public enum StateAlert {
  public struct Note: Equatable, Sendable {
    public let title: String
    public let body: String
  }

  public static func note(for new: MenuState, previous: MenuState) -> Note? {
    guard new != previous else { return nil }
    switch new {
    case .stalled:
      return Note(title: "Earnings stalled",
                  body: "You're active but earnings haven't moved — VS Code may have stopped serving ads.")
    case .cap:
      return Note(title: "Daily cap reached", body: "You've hit today's earnings cap.")
    case .killed:
      return Note(title: "Not earning",
                  body: "The Kickbacks extension looks stopped or signed out in VS Code.")
    case .earning:
      switch previous {
      case .stalled, .killed: return Note(title: "Earning again", body: "Kickbacks is back to earning.")
      default: return nil           // cap / no-serve aren't failures → no "recovered" ping
      }
    case .noServe, .signedOut:
      return nil                     // idle / signed-out are benign — don't nag
    }
  }
}
