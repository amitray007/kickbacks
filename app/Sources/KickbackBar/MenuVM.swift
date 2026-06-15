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
  @Published private(set) var menuBarStyle: MenuBarStyle = .today   // what the menu bar shows
  @Published private(set) var hideAmounts = false      // mask $ amounts (for screen sharing)
  @Published private(set) var demoMode = false         // show fake demo data
  @Published private(set) var lastUpdated: Date?       // when a fresh model was last applied — drives "Updated Nm ago"
  @Published private(set) var hourlyCapUsd: Double = 20    // personal hourly cap (editable in Settings)
  @Published private(set) var dailyCapUsd: Double = 200    // personal daily cap (editable in Settings)

  // Generated once per launch so Demo mode is stable across toggles (re-rolls only on restart).
  private let demoModel = MenuModel.makeDemo()
  private let demoHistory = HistoryModel.makeDemo()

  private var pollTask: Task<Void, Never>?
  private var loginProc: Process?
  private var loginWatch: Task<Void, Never>?
  private var lastNotifiedState: MenuState?   // edge-trigger for alert notifications
  private var milestoneSeen: Double?          // highest lifetime milestone already notified (persisted)

  private static let intervalKey = "refreshIntervalSeconds"

  init() {
    let stored = UserDefaults.standard.integer(forKey: Self.intervalKey)
    pollSeconds = stored > 0 ? max(15, stored) : 60
    menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .today
    hideAmounts = UserDefaults.standard.bool(forKey: "hideAmounts")
    demoMode = UserDefaults.standard.bool(forKey: "demoMode")
    hourlyCapUsd = UserDefaults.standard.object(forKey: "hourlyCapUsd") as? Double ?? 20
    dailyCapUsd = UserDefaults.standard.object(forKey: "dailyCapUsd") as? Double ?? 200
    milestoneSeen = UserDefaults.standard.object(forKey: "milestoneSeen") as? Double
    refresh()
    startPolling()
  }

  deinit { pollTask?.cancel(); loginWatch?.cancel(); retryTask?.cancel() }

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

  func setMenuBarStyle(_ s: MenuBarStyle) { menuBarStyle = s; UserDefaults.standard.set(s.rawValue, forKey: "menuBarStyle") }
  func setHideAmounts(_ on: Bool) { hideAmounts = on; UserDefaults.standard.set(on, forKey: "hideAmounts") }
  func setDemoMode(_ on: Bool) { demoMode = on; UserDefaults.standard.set(on, forKey: "demoMode") }
  func setHourlyCap(_ v: Double) { hourlyCapUsd = max(0, v); UserDefaults.standard.set(hourlyCapUsd, forKey: "hourlyCapUsd") }
  func setDailyCap(_ v: Double) { dailyCapUsd = max(0, v); UserDefaults.standard.set(dailyCapUsd, forKey: "dailyCapUsd") }

  /// Effective display values — swap in the cached demo data when demoMode is on.
  var effModel: MenuModel { demoMode ? demoModel : model }
  var effHistory: HistoryModel? { demoMode ? demoHistory : history }
  var effPhase: AuthPhase { demoMode ? .signedIn : phase }

  /// `showSpinner` is set only by the Refresh button so the 60s background poll doesn't
  /// flicker the spinner. The model is kept on a transient (nil) fetch.
  func refresh(showSpinner: Bool = false) {
    if showSpinner { refreshing = true }
    Task.detached(priority: .utility) {
      let m = ModelClient.fetch()
      let h = ModelClient.history()
      await MainActor.run {
        if let m {
          self.apply(m); self.loading = false             // first model resolves the loading state
          self.fetchFails = 0; self.retryTask?.cancel()    // recovered → stop retrying
        } else {
          self.scheduleRetry()                             // transient failure → quick retry, not a full interval
        }
        if let h { self.history = h }
        if showSpinner { self.refreshing = false }
      }
    }
  }

  private var fetchFails = 0
  private var retryTask: Task<Void, Never>?

  /// On a transient fetch failure, retry a few times with short backoff (5/10/15s) before
  /// falling back to the normal poll cadence. Resets once a fetch succeeds.
  private func scheduleRetry() {
    guard !demoMode, fetchFails < 3 else { return }
    fetchFails += 1
    retryTask?.cancel()
    let delay = UInt64(5 * fetchFails)
    retryTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
      if !Task.isCancelled { self?.refresh() }
    }
  }

  private func apply(_ m: MenuModel) {
    model = m
    lastUpdated = Date()   // a fresh model arrived = data is current as of now
    if phase == .signingIn {
      if m.signedIn { finishLogin(.signedIn) }   // login completed
    } else {
      phase = m.signedIn ? .signedIn : .signedOut
    }
    handleAlerts(m)
    handleMilestone(m)
  }

  /// Fire a native notification on signed-in state transitions (edge-triggered; the
  /// first signed-in model just seeds the baseline without notifying).
  private func handleAlerts(_ m: MenuModel) {
    guard m.signedIn else { lastNotifiedState = nil; return }
    if let prev = lastNotifiedState, let note = StateAlert.note(for: m.state, previous: prev) {
      Notifier.fire(note)
    }
    lastNotifiedState = m.state
  }

  /// Notify when lifetime earnings cross a new milestone. The first signed-in model seeds the
  /// baseline silently so we don't alert for milestones passed before the app was installed.
  private func handleMilestone(_ m: MenuModel) {
    guard m.signedIn else { return }
    let level = MilestoneAlert.highestCrossed(m.lifetimeUsd)
    if let last = milestoneSeen, level > last {
      Notifier.fire(title: "🎉 Kickbacks milestone", body: "You've earned $\(Int(level)) all-time!", id: "ai.kickback.milestone")
    }
    if milestoneSeen == nil || level > (milestoneSeen ?? 0) {
      milestoneSeen = level
      UserDefaults.standard.set(level, forKey: "milestoneSeen")
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
