// app/Sources/KickbacksBar/MenuVM.swift
import SwiftUI
import AppKit
import KickbacksKit

/// UI phase for the update flow (the available release itself lives in `availableUpdate`).
enum UpdateState: Equatable { case idle, checking, available, updating, failed }

/// Holds the polled model + a small auth phase machine. Normal polling sets the phase
/// from `model.signedIn`; `signIn()` overrides it with `.signingIn` while the spawned
/// `kickbacks login` runs, polling until the model reports signed-in (or it times out).
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
  @Published private(set) var showDemoLabel = true     // show "Demo mode" label in bottom bar
  @Published private(set) var pinned = false           // floating mini HUD visible
  @Published private(set) var lastUpdated: Date?       // when a fresh model was last applied — drives "Updated Nm ago"
  @Published private(set) var hourlyCapUsd: Double = 20    // personal hourly cap (editable in Settings)
  @Published private(set) var dailyCapUsd: Double = 200    // personal daily cap (editable in Settings)

  // Updates
  @Published private(set) var availableUpdate: Release?           // non-nil ⇒ banner shows
  @Published private(set) var updateState: UpdateState = .idle
  @Published private(set) var updateLog: [String] = []           // streamed brew output (tail)
  @Published private(set) var updateCheckResult: String?         // inline feedback for "Check now"
  @Published private(set) var currentVersionString = "—"         // shown in Settings (cached)
  @Published private(set) var autoCheckUpdates = true
  @Published private(set) var updateCheckHours = 24
  private var skippedVersion = ""
  private var lastNotifiedUpdateVersion: String?
  private var updateCheckTask: Task<Void, Never>?
  private let installMethodCached = Updater.installMethod()   // install method can't change at runtime

  // Generated once per launch so Demo mode is stable across toggles (re-rolls only on restart).
  private let demoModel = MenuModel.makeDemo()
  private let demoHistory = HistoryModel.makeDemo()
  private var mini: MiniWindowController?

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
    showDemoLabel = UserDefaults.standard.object(forKey: "showDemoLabel") as? Bool ?? true
    hourlyCapUsd = UserDefaults.standard.object(forKey: "hourlyCapUsd") as? Double ?? 20
    dailyCapUsd = UserDefaults.standard.object(forKey: "dailyCapUsd") as? Double ?? 200
    milestoneSeen = UserDefaults.standard.object(forKey: "milestoneSeen") as? Double
    pinned = UserDefaults.standard.bool(forKey: "miniPinned")
    let controller = MiniWindowController(content: { [weak self] in
      guard let self else { return AnyView(EmptyView()) }
      return AnyView(MiniView(vm: self))
    })
    mini = controller
    if pinned { Task { controller.setVisible(true) } }   // defer until after launch settles
    autoCheckUpdates = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true
    updateCheckHours = UserDefaults.standard.object(forKey: "updateCheckHours") as? Int ?? 24
    skippedVersion = UserDefaults.standard.string(forKey: "skippedUpdateVersion") ?? ""
    Task { [weak self] in
      let v = await Task.detached { Updater.currentVersion() }.value
      self?.currentVersionString = v ?? "—"
    }
    refresh()
    startPolling()
    startUpdateChecks()
  }

  deinit { pollTask?.cancel(); loginWatch?.cancel(); retryTask?.cancel(); updateCheckTask?.cancel() }

  // Multiplier applied to pollSeconds when the user is idle (no open IDE sessions).
  // 1 = normal cadence; 5 = 5× slower. Resets to 1 when the next model reports active.
  private var idleMultiplier: UInt64 = 1

  private func startPolling() {
    pollTask?.cancel()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        let delay = UInt64(self?.pollSeconds ?? 60) * (self?.idleMultiplier ?? 1)
        try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
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
  func setShowDemoLabel(_ on: Bool) { showDemoLabel = on; UserDefaults.standard.set(on, forKey: "showDemoLabel") }
  func setHourlyCap(_ v: Double) { hourlyCapUsd = max(0, v); UserDefaults.standard.set(hourlyCapUsd, forKey: "hourlyCapUsd") }
  func setDailyCap(_ v: Double) { dailyCapUsd = max(0, v); UserDefaults.standard.set(dailyCapUsd, forKey: "dailyCapUsd") }
  func setPinned(_ on: Bool) { pinned = on; UserDefaults.standard.set(on, forKey: "miniPinned"); mini?.setVisible(on) }

  func setAutoCheckUpdates(_ on: Bool) {
    autoCheckUpdates = on
    UserDefaults.standard.set(on, forKey: "autoCheckUpdates")
    startUpdateChecks()
  }

  func setUpdateCheckHours(_ h: Int) {
    updateCheckHours = max(1, h)
    UserDefaults.standard.set(updateCheckHours, forKey: "updateCheckHours")
    startUpdateChecks()
  }

  /// Initial check shortly after launch, then every `updateCheckHours`. No-op if auto-check is off.
  private func startUpdateChecks() {
    updateCheckTask?.cancel()
    guard autoCheckUpdates else { return }
    let hours = UInt64(max(1, updateCheckHours))
    updateCheckTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)   // let launch settle
      await self?.checkForUpdates()
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: hours * 3600 * 1_000_000_000)
        if Task.isCancelled { return }
        await self?.checkForUpdates()
      }
    }
  }

  /// Fetch the latest release and compare to the installed version. `manual` adds inline
  /// feedback for the Settings "Check now" button; auto checks notify once per new version.
  func checkForUpdates(manual: Bool = false) async {
    guard updateState != .updating else { return }   // don't disturb an in-progress upgrade
    updateState = .checking
    updateCheckResult = nil
    let latest = await Updater.fetchLatest()
    let current = await Task.detached { Updater.currentVersion() }.value ?? ""
    currentVersionString = current.isEmpty ? "—" : current
    guard let latest else {
      updateState = availableUpdate == nil ? .idle : .available
      if manual { updateCheckResult = "Couldn't check for updates." }
      return
    }
    if Updater.isNewer(latest.version, than: current), latest.version != skippedVersion {
      availableUpdate = latest
      updateState = .available
      if manual {
        updateCheckResult = "Update available: v\(latest.version)"
      } else if lastNotifiedUpdateVersion != latest.version {
        lastNotifiedUpdateVersion = latest.version
        Notifier.fire(title: "Kickbacks v\(latest.version) is available",
                      body: "Open Kickbacks to see what's new and update.",
                      id: "ai.kickbacks.update")
      }
    } else {
      availableUpdate = nil
      updateState = .idle
      if manual { updateCheckResult = "You're up to date (v\(current))." }
    }
  }

  /// Begin the upgrade. Homebrew installs run `brew upgrade` in the background and relaunch;
  /// other installs open the release page (brew can't update them).
  func startUpdate() {
    let brewPath: String?
    let isCask: Bool
    switch installMethodCached {
    case .homebrew(let p):     brewPath = p; isCask = false
    case .homebrewCask(let p): brewPath = p; isCask = true
    default:
      if let u = availableUpdate.flatMap({ URL(string: $0.htmlURL) }) { NSWorkspace.shared.open(u) }
      return
    }
    guard let brewPath else { return }
    updateState = .updating
    updateLog = []
    UpdateRunner.upgrade(brewPath: brewPath, isCask: isCask, onLine: { [weak self] line in
      Task { @MainActor in
        guard let self else { return }
        self.updateLog.append(line)
        if self.updateLog.count > 200 { self.updateLog.removeFirst(self.updateLog.count - 200) }
      }
    }, completion: { [weak self] ok in
      Task { @MainActor in
        guard let self else { return }
        if ok {
          if isCask {
            Notifier.fire(title: "Kickbacks updated", body: "Relaunching the latest version…", id: "ai.kickbacks.update")
            UpdateRunner.relaunchCask()
          } else if UpdateRunner.barAgentInstalled() {
            Notifier.fire(title: "Kickbacks updated", body: "Relaunching the latest version…", id: "ai.kickbacks.update")
            UpdateRunner.relaunch()
          } else {
            Notifier.fire(title: "Kickbacks updated", body: "Quit and reopen Kickbacks to finish.", id: "ai.kickbacks.update")
            self.availableUpdate = nil
            self.updateState = .idle
          }
        } else {
          self.updateState = .failed
        }
      }
    })
  }

  /// Suppress the current available version until a newer one appears.
  func skipUpdate() {
    if let v = availableUpdate?.version {
      skippedVersion = v
      UserDefaults.standard.set(v, forKey: "skippedUpdateVersion")
    }
    availableUpdate = nil
    updateState = .idle
  }

  /// Whether the current install can self-update via brew (drives the primary button label).
  var canBrewUpdate: Bool {
    switch installMethodCached {
    case .homebrew, .homebrewCask: return true
    default: return false
    }
  }

  /// Effective display values — swap in the cached demo data when demoMode is on.
  var effModel: MenuModel { demoMode ? demoModel : model }
  var effHistory: HistoryModel? { demoMode ? demoHistory : history }
  var effPhase: AuthPhase { demoMode ? .signedIn : phase }

  /// In demo mode, prefer real ads if any exist; only fall back to demo ads when there are none.
  var effRecentAds: [AdItem] { demoMode && model.recentAds.isEmpty ? demoModel.recentAds : model.recentAds }

  /// `showSpinner` is set only by the Refresh button so the 60s background poll doesn't
  /// flicker the spinner. The model is kept on a transient (nil) fetch.
  /// Implicit (panel-open) calls are debounced: skipped if a fetch ran in the last 10s.
  func refresh(showSpinner: Bool = false) {
    let isImplicit = !showSpinner
    if isImplicit, let last = lastFetchTime, Date().timeIntervalSince(last) < 10 { return }
    lastFetchTime = Date()
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
  private var lastFetchTime: Date?

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
    // Back off to 5× the normal interval when the user has no open IDE sessions.
    // active == nil means the CLI didn't emit the field (old version) → keep current multiplier.
    if let isActive = m.active { idleMultiplier = isActive ? 1 : 5 }
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
      Notifier.fire(title: "🎉 Kickbacks milestone", body: "You've earned $\(Int(level)) all-time!", id: "ai.kickbacks.milestone")
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
