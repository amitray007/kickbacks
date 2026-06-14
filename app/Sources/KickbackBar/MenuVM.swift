// app/Sources/KickbackBar/MenuVM.swift
import SwiftUI
import KickbackKit

/// Holds the polled model + a small auth phase machine. Normal polling sets the phase
/// from `model.signedIn`; `signIn()` overrides it with `.signingIn` while the spawned
/// `kickback login` runs, polling until the model reports signed-in (or it times out).
@MainActor final class MenuVM: ObservableObject {
  @Published private(set) var model: MenuModel = .signedOut
  @Published private(set) var phase: AuthPhase = .signedOut
  @Published private(set) var refreshing = false   // true only during a user-initiated refresh
  @Published private(set) var history: HistoryModel?   // local stats, shown inline

  private var pollTask: Task<Void, Never>?
  private var loginProc: Process?
  private var loginWatch: Task<Void, Never>?

  init(intervalSeconds: UInt64 = 60) {
    refresh()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
        self?.refresh()
      }
    }
  }

  deinit { pollTask?.cancel(); loginWatch?.cancel() }

  /// `showSpinner` is set only by the Refresh button so the 60s background poll doesn't
  /// flicker the spinner. The model is kept on a transient (nil) fetch.
  func refresh(showSpinner: Bool = false) {
    if showSpinner { refreshing = true }
    Task.detached(priority: .utility) {
      let m = ModelClient.fetch()
      let h = ModelClient.history()
      await MainActor.run {
        if let m { self.apply(m) }
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
    Task.detached { ModelClient.logout(); await MainActor.run { self.refresh() } }
  }

  private func finishLogin(_ p: AuthPhase) {
    loginWatch?.cancel(); loginWatch = nil
    loginProc = nil
    phase = p
    refresh()
  }
}
