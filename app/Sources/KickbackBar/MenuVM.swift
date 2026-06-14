// app/Sources/KickbackBar/MenuVM.swift
import SwiftUI
import KickbackKit

/// Holds the polled model + a small auth phase machine. Normal polling sets the phase
/// from `model.signedIn`; `signIn()` overrides it with `.signingIn` while the spawned
/// `kickback login` runs, polling until the model reports signed-in (or it times out).
@MainActor final class MenuVM: ObservableObject {
  @Published private(set) var model: MenuModel = .signedOut
  @Published private(set) var phase: AuthPhase = .signedOut

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

  func refresh() {
    Task.detached(priority: .utility) {
      guard let m = ModelClient.fetch() else { return } // nil = transient → keep last
      await MainActor.run { self.apply(m) }
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
