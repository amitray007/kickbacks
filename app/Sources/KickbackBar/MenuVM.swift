import SwiftUI
import KickbackKit

/// Holds the current menu model and refreshes it (off the main thread) on a timer
/// and on demand. The blocking CLI spawn runs in a detached task; the published
/// update hops back to the main actor.
@MainActor final class MenuVM: ObservableObject {
  @Published private(set) var model: MenuModel = .signedOut
  private var pollTask: Task<Void, Never>?

  init(intervalSeconds: UInt64 = 60) {
    refresh()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
        self?.refresh()
      }
    }
  }

  deinit { pollTask?.cancel() }

  func refresh() {
    Task.detached(priority: .utility) {
      let m = ModelClient.fetch()
      await MainActor.run { self.model = m }
    }
  }
}
