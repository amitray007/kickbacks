// app/Sources/KickbackBar/MenuVM.swift
import SwiftUI
import KickbackKit

/// Holds the polled model + a small auth phase machine. Normal polling sets the phase
/// from `model.signedIn`; `signIn()` overrides it with `.signingIn` while the spawned
/// `kickback login` runs, polling until the model reports signed-in (or it times out).
@MainActor final class MenuVM: ObservableObject {
  @Published private(set) var model: MenuModel = .signedOut
  @Published private(set) var phase: AuthPhase = .signedOut
  @Published private(set) var loading = true       // true until the first fetch resolves (no "Sign in" flash on launch)
  @Published private(set) var refreshing = false   // true only during a user-initiated refresh
  @Published private(set) var history: HistoryModel?   // local stats, shown inline
  @Published private(set) var pollSeconds: Int = 60    // auto-refresh cadence (persisted)

  private var pollTask: Task<Void, Never>?
  private var loginProc: Process?
  private var loginWatch: Task<Void, Never>?

  private static let intervalKey = "refreshIntervalSeconds"

  init() {
    let stored = UserDefaults.standard.integer(forKey: Self.intervalKey)
    pollSeconds = stored > 0 ? max(15, stored) : 60
    refresh()
    startPolling()
  }

  deinit { pollTask?.cancel(); loginWatch?.cancel() }

  private func startPolling() {
    pollTask?.cancel()
    let secs = pollSeconds
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
        self?.refresh()
      }
    }
  }

  /// Change the auto-refresh cadence (persisted), restart the timer, and refresh now.
  func setPollSeconds(_ s: Int) {
    pollSeconds = max(15, s)
    UserDefaults.standard.set(pollSeconds, forKey: Self.intervalKey)
    startPolling()
    refresh()
  }

  /// `showSpinner` is set only by the Refresh button so the 60s background poll doesn't
  /// flicker the spinner. The model is kept on a transient (nil) fetch.
  func refresh(showSpinner: Bool = false) {
    if showSpinner { refreshing = true }
    Task.detached(priority: .utility) {
      let m = ModelClient.fetch()
      let h = ModelClient.history()
      await MainActor.run {
        if let m { self.apply(m); self.loading = false }   // first model resolves the loading state
        if let h { self.history = h }
        if showSpinner { self.refreshing = false }
      }
    }
  }

  private func apply(_ m: MenuModel) {
    model = m
    if phase == .signingIn {
      if m.signedIn { finishLogin(.signedIn) }   // login completed
    } else {
      phase = m.signedIn ? .signedIn : .signedOut
    }
  }

  func signIn() {
    guard phase != .signingIn else { return }
    phase = .signingIn
    loginProc = ModelClient.startLogin()
    guard loginProc != nil else { phase = .signedOut; return }
    loginWatch = Task { [weak self] in
      for _ in 0..<60 {                                   // ~2 min at 2s
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if Task.isCancelled { return }
        if let m = ModelClient.fetch(), m.signedIn {
          await MainActor.run { self?.apply(m) }
          return
        }
      }
      await MainActor.run { self?.finishLogin(.signedOut) } // timed out
    }
  }

  func cancelLogin() {
    loginProc?.terminate()
    finishLogin(.signedOut)
  }

  func signOut() {
    // Optimistic: flip to signed-out instantly; clear tokens + revoke server session in the background.
    phase = .signedOut
    model = .signedOut
    history = nil
    loading = false
    Task.detached { ModelClient.logout() }
  }

  private func finishLogin(_ p: AuthPhase) {
    loginWatch?.cancel(); loginWatch = nil
    loginProc = nil
    phase = p
    refresh()
  }
}
