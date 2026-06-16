# In-App Updates (Mac menu-bar app) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Ghostty-style in-app update flow to the Kickbacks menu-bar app — a background check against the GitHub release API, a changelog window, and a user-initiated `brew upgrade` that runs detached and relaunches via `launchctl`.

**Architecture:** A pure, testable `Updater` engine in `KickbacksKit` (version parsing, GitHub release fetch/parse, install-method classification) + an impure `UpdateRunner` in `KickbacksBar` (streams `brew upgrade`, relaunches). `MenuVM` gains update state, a periodic check timer, and the persisted prefs; `MenuContent` shows a banner; a new `UpdateView` window shows the changelog; `SettingsView` gets an "Updates" section.

**Tech Stack:** Swift 6, SwiftUI (`MenuBarExtra`/`Window`), `Process`/`Pipe`, `URLSession` async, `UNUserNotifications`, `launchctl`, Swift Package Manager + XCTest.

**Branch:** `feat/mac-auto-update` (already created). All commits end with the standard trailer:
```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

**Spec:** `docs/superpowers/specs/2026-06-16-mac-auto-update-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `app/Sources/KickbacksKit/Updater.swift` | **new** — `Release`, `InstallMethod`, pure helpers (`parseVersion`, `isNewer`, `parseRelease`, `classify`) + impure wrappers (`currentVersion`, `fetchLatest`, `installMethod`) |
| `app/Tests/KickbacksKitTests/UpdaterTests.swift` | **new** — unit tests for the pure helpers |
| `app/Sources/KickbacksBar/UpdateRunner.swift` | **new** — runs `brew upgrade` detached, streams output, relaunches via `launchctl` |
| `app/Sources/KickbacksBar/UpdateView.swift` | **new** — the update window (version, date, changelog, actions, live log) |
| `app/Sources/KickbacksBar/MenuVM.swift` | update state, check timer, `startUpdate`/`skipUpdate`, persisted prefs, cached version string |
| `app/Sources/KickbacksBar/MenuContent.swift` | conditional "Update available" banner + `openUpdate()` |
| `app/Sources/KickbacksBar/SettingsView.swift` | "Updates" section |
| `app/Sources/KickbacksBar/KickbacksBarApp.swift` | register the `update` `Window` scene |

**Note on the prerelease simplification:** `parseVersion` strips any `-prerelease`/`+build` suffix and compares the numeric `MAJOR.MINOR.PATCH` only. The GitHub `/releases/latest` endpoint already excludes prereleases, so "latest" is always a stable tag; this keeps the comparator simple and guarantees a malformed version never produces a false "update available" prompt.

---

## Task 1: `Updater` pure core (types + parsing + classification)

**Files:**
- Create: `app/Sources/KickbacksKit/Updater.swift`
- Test: `app/Tests/KickbacksKitTests/UpdaterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `app/Tests/KickbacksKitTests/UpdaterTests.swift`:

```swift
import XCTest
@testable import KickbacksKit

final class UpdaterTests: XCTestCase {
  func testParseVersionVariants() {
    XCTAssertTrue(Updater.parseVersion("v0.2.0")! == (0, 2, 0))
    XCTAssertTrue(Updater.parseVersion("0.10.0")! == (0, 10, 0))
    XCTAssertTrue(Updater.parseVersion("1.2")! == (1, 2, 0))
    XCTAssertTrue(Updater.parseVersion("0.2.0-beta.1")! == (0, 2, 0))
    XCTAssertNil(Updater.parseVersion("garbage"))
    XCTAssertNil(Updater.parseVersion("1.x.3"))
  }

  func testIsNewer() {
    XCTAssertTrue(Updater.isNewer("0.2.0", than: "0.1.0"))
    XCTAssertTrue(Updater.isNewer("v0.2.0", than: "0.1.0"))   // tolerates leading v
    XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.0"))   // numeric, not lexical
    XCTAssertFalse(Updater.isNewer("0.2.0", than: "0.2.0"))   // equal
    XCTAssertFalse(Updater.isNewer("0.1.0", than: "0.2.0"))   // older
    XCTAssertFalse(Updater.isNewer("garbage", than: "0.1.0")) // never a false prompt
  }

  func testParseRelease() {
    let json = #"{"tag_name":"v0.2.0","body":"## What's new\n- A\n- B","html_url":"https://github.com/amitray007/kickbacks/releases/tag/v0.2.0","published_at":"2026-06-16T08:00:00Z"}"#
    let r = Updater.parseRelease(Data(json.utf8))
    XCTAssertEqual(r?.version, "0.2.0")  // leading v stripped
    XCTAssertEqual(r?.notes, "## What's new\n- A\n- B")
    XCTAssertEqual(r?.htmlURL, "https://github.com/amitray007/kickbacks/releases/tag/v0.2.0")
    XCTAssertEqual(r?.publishedAt, "2026-06-16T08:00:00Z")
    XCTAssertNil(Updater.parseRelease(Data("not json".utf8)))
    XCTAssertNil(Updater.parseRelease(Data(#"{"body":"x"}"#.utf8)))  // no tag_name
  }

  func testClassifyHomebrewBySibling() {
    let m = Updater.classify(
      executablePath: "/opt/homebrew/Cellar/kickbacks/0.2.0/bin/kickbacks-bar",
      cliPath: "/opt/homebrew/bin/kickbacks",
      exists: { $0 == "/opt/homebrew/bin/brew" })
    XCTAssertEqual(m, .homebrew(brewPath: "/opt/homebrew/bin/brew"))
  }

  func testClassifyAppBundle() {
    let m = Updater.classify(
      executablePath: "/Applications/Kickbacks.app/Contents/MacOS/KickbacksBar",
      cliPath: "/Applications/Kickbacks.app/Contents/MacOS/kickbacks",
      exists: { _ in false })
    XCTAssertEqual(m, .appBundle)
  }

  func testClassifyUnknown() {
    let m = Updater.classify(
      executablePath: "/Users/x/dev/.build/release/KickbacksBar",
      cliPath: nil,
      exists: { _ in false })
    XCTAssertEqual(m, .unknown)
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path app --filter UpdaterTests`
Expected: **build error** — `cannot find 'Updater' in scope` (the type doesn't exist yet). That is the red state.

- [ ] **Step 3: Implement the pure core**

Create `app/Sources/KickbacksKit/Updater.swift`:

```swift
import Foundation

/// A published GitHub release, normalized for display + comparison.
public struct Release: Equatable, Sendable {
  public let version: String      // numeric, no leading "v" — e.g. "0.2.0"
  public let notes: String        // GitHub release body (markdown)
  public let htmlURL: String
  public let publishedAt: String  // ISO-8601, for display

  public init(version: String, notes: String, htmlURL: String, publishedAt: String) {
    self.version = version; self.notes = notes; self.htmlURL = htmlURL; self.publishedAt = publishedAt
  }
}

/// How this build was installed — decides whether `brew upgrade` is the update path.
public enum InstallMethod: Equatable, Sendable {
  case homebrew(brewPath: String)
  case appBundle   // /Applications/Kickbacks.app — release-page fallback
  case unknown     // dev / other — release-page fallback
}

/// Update engine. Pure helpers (`parseVersion`/`isNewer`/`parseRelease`/`classify`) are
/// unit-tested; the impure wrappers (`currentVersion`/`fetchLatest`/`installMethod`) are
/// thin shells over them and are exercised manually.
public enum Updater {
  static let repoSlug = "amitray007/kickbacks"

  /// Parse "v1.2.3" / "1.2" / "0.2.0-beta" into numeric components. Suffixes after the
  /// first '-' or '+' are dropped. Returns nil if any present component isn't an integer.
  static func parseVersion(_ s: String) -> (Int, Int, Int)? {
    var str = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if str.hasPrefix("v") || str.hasPrefix("V") { str.removeFirst() }
    if let i = str.firstIndex(where: { $0 == "-" || $0 == "+" }) { str = String(str[..<i]) }
    guard !str.isEmpty else { return nil }
    let parsed = str.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
    let nums = parsed.compactMap { $0 }
    return (nums.count > 0 ? nums[0] : 0, nums.count > 1 ? nums[1] : 0, nums.count > 2 ? nums[2] : 0)
  }

  /// True only when `latest` is strictly greater by numeric semver. Parse failure → false.
  public static func isNewer(_ latest: String, than current: String) -> Bool {
    guard let l = parseVersion(latest), let c = parseVersion(current) else { return false }
    return l > c   // Swift compares (Int,Int,Int) tuples lexicographically by element
  }

  /// Strip a leading "v" from a tag for display/comparison.
  static func normalize(_ tag: String) -> String {
    var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
    return s
  }

  /// Map GitHub's release JSON to a `Release`. nil on bad JSON or a missing tag.
  static func parseRelease(_ data: Data) -> Release? {
    struct GHRelease: Decodable { let tag_name: String; let body: String?; let html_url: String; let published_at: String? }
    guard let r = try? JSONDecoder().decode(GHRelease.self, from: data) else { return nil }
    let v = normalize(r.tag_name)
    guard !v.isEmpty else { return nil }
    return Release(version: v, notes: r.body ?? "", htmlURL: r.html_url, publishedAt: r.published_at ?? "")
  }

  /// Pure install-method classifier (paths + an existence probe are injected for tests).
  /// Prefers a `brew` sibling of the resolved CLI; else a brew prefix on the running binary;
  /// else an `.app` bundle; else unknown.
  static func classify(executablePath: String, cliPath: String?, exists: (String) -> Bool) -> InstallMethod {
    if let cli = cliPath {
      let dir = (cli as NSString).deletingLastPathComponent
      let brew = (dir as NSString).appendingPathComponent("brew")
      if exists(brew) { return .homebrew(brewPath: brew) }
    }
    if executablePath.contains("/Cellar/") || executablePath.hasPrefix("/opt/homebrew/") || executablePath.hasPrefix("/usr/local/") {
      for b in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where exists(b) { return .homebrew(brewPath: b) }
    }
    if executablePath.contains(".app/Contents/MacOS/") { return .appBundle }
    return .unknown
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path app --filter UpdaterTests`
Expected: **PASS** — all 6 tests green.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/KickbacksKit/Updater.swift app/Tests/KickbacksKitTests/UpdaterTests.swift
git commit -m "feat(app): Updater core — semver compare, release parse, install detection"
```

---

## Task 2: `Updater` impure wrappers (version, fetch, install method)

**Files:**
- Modify: `app/Sources/KickbacksKit/Updater.swift` (append to the `Updater` enum)

- [ ] **Step 1: Add the wrappers**

Append these inside the `Updater` enum in `app/Sources/KickbacksKit/Updater.swift` (before the closing `}`):

```swift
  /// The installed version, via `kickbacks --version`; falls back to the .app Info.plist.
  /// nil only if neither is available (no CLI + no bundle version).
  public static func currentVersion() -> String? {
    if let bin = ModelClient.binaryPath() {
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: bin)
      proc.arguments = ["--version"]
      let out = Pipe(); proc.standardOutput = out; proc.standardError = Pipe()
      if (try? proc.run()) != nil {
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus == 0,
           let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
          return s
        }
      }
    }
    return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
  }

  /// Anonymous, read-only GET of this repo's latest stable release. nil on any failure.
  public static func fetchLatest() async -> Release? {
    guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else { return nil }
    var req = URLRequest(url: url)
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.setValue("kickbacks-bar", forHTTPHeaderField: "User-Agent")   // GitHub rejects UA-less requests
    req.timeoutInterval = 15
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
      return parseRelease(data)
    } catch { return nil }
  }

  /// Real install-method detection from the running binary + resolved CLI.
  public static func installMethod() -> InstallMethod {
    let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? ""
    return classify(executablePath: exe, cliPath: ModelClient.binaryPath()) {
      FileManager.default.isExecutableFile(atPath: $0)
    }
  }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build --package-path app`
Expected: **Build complete** (no errors). `ModelClient.binaryPath()` is `public` in the same module.

- [ ] **Step 3: Run the full test suite (no regressions)**

Run: `swift test --package-path app`
Expected: **PASS** — existing tests + `UpdaterTests` all green.

- [ ] **Step 4: Commit**

```bash
git add app/Sources/KickbacksKit/Updater.swift
git commit -m "feat(app): Updater wrappers — kickbacks --version, GitHub fetch, install method"
```

---

## Task 3: `UpdateRunner` — background `brew upgrade` + relaunch

**Files:**
- Create: `app/Sources/KickbacksBar/UpdateRunner.swift`

- [ ] **Step 1: Implement the runner**

Create `app/Sources/KickbacksBar/UpdateRunner.swift`:

```swift
import Foundation
import AppKit

/// Runs `brew upgrade kickbacks` detached, streaming output line-by-line, then relaunches
/// the menu-bar app via launchd. All callbacks are delivered on the main queue.
enum UpdateRunner {
  /// Whether the `ai.kickbacks.bar` launchd agent is installed (file check — no spawn).
  static func barAgentInstalled() -> Bool {
    let p = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/ai.kickbacks.bar.plist")
    return FileManager.default.fileExists(atPath: p)
  }

  /// `brew update && brew upgrade kickbacks` via a login shell (so brew's PATH/env is set).
  /// `onLine` fires per output line; `completion(true)` on exit status 0.
  static func upgrade(brewPath: String, onLine: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
    let brew = "'" + brewPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/sh")
    proc.arguments = ["-lc", "\(brew) update && \(brew) upgrade kickbacks"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { h in
      let d = h.availableData
      guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
      for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
        let str = String(line)
        DispatchQueue.main.async { onLine(str) }
      }
    }
    proc.terminationHandler = { p in
      pipe.fileHandleForReading.readabilityHandler = nil
      let ok = p.terminationStatus == 0
      DispatchQueue.main.async { completion(ok) }
    }
    do { try proc.run() } catch { DispatchQueue.main.async { completion(false) } }
  }

  /// Kickstart the launchd bar agent so the new binary replaces this process, then exit.
  static func relaunch() {
    let label = "gui/\(getuid())/ai.kickbacks.bar"
    let helper = Process()
    helper.executableURL = URL(fileURLWithPath: "/bin/sh")
    helper.arguments = ["-c", "sleep 1; launchctl kickstart -k \(label)"]
    try? helper.run()   // detached; do not wait — it will kill + relaunch us
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
  }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build --package-path app`
Expected: **Build complete**.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/KickbacksBar/UpdateRunner.swift
git commit -m "feat(app): UpdateRunner — detached brew upgrade with streamed log + relaunch"
```

---

## Task 4: `MenuVM` — update state, check timer, actions, prefs

**Files:**
- Modify: `app/Sources/KickbacksBar/MenuVM.swift`

- [ ] **Step 1: Add the `UpdateState` enum + `import AppKit`**

At the top of `app/Sources/KickbacksBar/MenuVM.swift`, change the imports (line 2-3) from:

```swift
import SwiftUI
import KickbacksKit
```

to:

```swift
import SwiftUI
import AppKit
import KickbacksKit

/// UI phase for the update flow (the available release itself lives in `availableUpdate`).
enum UpdateState: Equatable { case idle, checking, available, updating, failed }
```

- [ ] **Step 2: Add the published properties**

In `MenuVM`, immediately after the `dailyCapUsd` property (line 21), add:

```swift
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
```

- [ ] **Step 3: Load prefs + start checks in `init`**

In `init()`, immediately before the closing call to `refresh()` (line 52, `refresh()`), add:

```swift
    autoCheckUpdates = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true
    updateCheckHours = UserDefaults.standard.object(forKey: "updateCheckHours") as? Int ?? 24
    skippedVersion = UserDefaults.standard.string(forKey: "skippedUpdateVersion") ?? ""
    Task.detached { [weak self] in
      let v = Updater.currentVersion()
      await MainActor.run { self?.currentVersionString = v ?? "—" }
    }
```

Then at the very end of `init()`, immediately after `startPolling()` (line 53), add:

```swift
    startUpdateChecks()
```

- [ ] **Step 4: Cancel the task in `deinit`**

Change `deinit` (line 56) from:

```swift
  deinit { pollTask?.cancel(); loginWatch?.cancel(); retryTask?.cancel() }
```

to:

```swift
  deinit { pollTask?.cancel(); loginWatch?.cancel(); retryTask?.cancel(); updateCheckTask?.cancel() }
```

- [ ] **Step 5: Add the update methods**

In `MenuVM`, immediately after `setPinned(_:)` (line 82), add:

```swift
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
    guard case let .homebrew(brewPath) = Updater.installMethod() else {
      if let u = availableUpdate.flatMap({ URL(string: $0.htmlURL) }) { NSWorkspace.shared.open(u) }
      return
    }
    updateState = .updating
    updateLog = []
    UpdateRunner.upgrade(brewPath: brewPath, onLine: { [weak self] line in
      guard let self else { return }
      self.updateLog.append(line)
      if self.updateLog.count > 200 { self.updateLog.removeFirst(self.updateLog.count - 200) }
    }, completion: { [weak self] ok in
      guard let self else { return }
      if ok {
        if UpdateRunner.barAgentInstalled() {
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
    if case .homebrew = Updater.installMethod() { return true }
    return false
  }
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build --package-path app`
Expected: **Build complete**.

- [ ] **Step 7: Run the full test suite (no regressions)**

Run: `swift test --package-path app`
Expected: **PASS**.

- [ ] **Step 8: Commit**

```bash
git add app/Sources/KickbacksBar/MenuVM.swift
git commit -m "feat(app): MenuVM update state, periodic check, brew upgrade + skip actions"
```

---

## Task 5: `UpdateView` — the changelog window

**Files:**
- Create: `app/Sources/KickbacksBar/UpdateView.swift`

- [ ] **Step 1: Implement the view**

Create `app/Sources/KickbacksBar/UpdateView.swift`:

```swift
import SwiftUI
import AppKit
import KickbacksKit

/// The update window: version + date, the rendered changelog, and the action buttons.
/// While updating it shows a live log; the user can close it and the upgrade continues.
struct UpdateView: View {
  @ObservedObject var vm: MenuVM
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let up = vm.availableUpdate {
        header(up)
        Divider()
        if vm.updateState == .updating || vm.updateState == .failed {
          progressPane
        } else {
          changelog(up)
        }
        Divider()
        footer(up)
      } else {
        Text("You're up to date.").padding(24)
      }
    }
    .frame(width: 460, height: 460)
  }

  private func header(_ up: Release) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "arrow.down.circle.fill").font(.title).foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 2) {
        Text("Kickbacks v\(up.version)").font(.headline)
        Text(dateText(up.publishedAt).map { "Released \($0)" } ?? "A new version is available")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }.padding(16)
  }

  private func changelog(_ up: Release) -> some View {
    ScrollView {
      Text(markdown(up.notes))
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
  }

  private var progressPane: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        if vm.updateState == .updating { ProgressView().controlSize(.small) }
        Text(vm.updateState == .failed ? "Update failed." : "Updating — rebuilding from source, this can take a few minutes…")
          .font(.callout).foregroundStyle(vm.updateState == .failed ? .red : .primary)
      }
      ScrollView {
        Text(vm.updateLog.joined(separator: "\n"))
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: .infinity)
      .background(Color.secondary.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }.padding(16)
  }

  private func footer(_ up: Release) -> some View {
    HStack {
      if vm.updateState == .failed, let u = URL(string: up.htmlURL) {
        Button("Open release page") { NSWorkspace.shared.open(u) }
        Spacer()
        Button("Close") { dismiss() }
      } else if vm.updateState == .updating {
        Spacer()
        Button("Continue in background") { dismiss() }.keyboardShortcut(.defaultAction)
      } else {
        Button("Skip this version") { vm.skipUpdate(); dismiss() }
        Spacer()
        Button("Later") { dismiss() }
        Button(vm.canBrewUpdate ? "Update & Restart" : "Open release page") { vm.startUpdate() }
          .keyboardShortcut(.defaultAction)
      }
    }.padding(16)
  }

  /// Render the release markdown; fall back to plain text if it doesn't parse.
  private func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(s)
  }

  /// "Jun 16, 2026" from an ISO-8601 timestamp; nil if it doesn't parse.
  private func dateText(_ iso: String) -> String? {
    let f = ISO8601DateFormatter()
    guard let d = f.date(from: iso) else { return nil }
    let out = DateFormatter(); out.dateStyle = .medium; out.timeStyle = .none
    return out.string(from: d)
  }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build --package-path app`
Expected: **Build complete**.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/KickbacksBar/UpdateView.swift
git commit -m "feat(app): UpdateView — changelog window with background progress + actions"
```

---

## Task 6: Wire it in — Window scene, panel banner, Settings section

**Files:**
- Modify: `app/Sources/KickbacksBar/KickbacksBarApp.swift`
- Modify: `app/Sources/KickbacksBar/MenuContent.swift`
- Modify: `app/Sources/KickbacksBar/SettingsView.swift`

- [ ] **Step 1: Register the update Window scene**

In `app/Sources/KickbacksBar/KickbacksBarApp.swift`, immediately after the `Share` window block (lines 30-33), add:

```swift
    Window("Kickbacks Update", id: "update") {
      UpdateView(vm: vm)
    }
    .windowResizability(.contentSize)
```

- [ ] **Step 2: Add the banner + `openUpdate()` to the panel**

In `app/Sources/KickbacksBar/MenuContent.swift`, in `body`, change the top of the `VStack` (lines 33-34) from:

```swift
        header
        Divider()
```

to:

```swift
        header
        Divider()
        updateBanner
```

Then add the `updateBanner` view and `openUpdate()` method. Insert immediately after the `header` computed property's closing brace (after line 80, before `private var statusPill`):

```swift
  @ViewBuilder private var updateBanner: some View {
    if let up = vm.availableUpdate {
      Button { openUpdate() } label: {
        HStack(spacing: 6) {
          if vm.updateState == .updating {
            ProgressView().controlSize(.small)
            Text("Updating to v\(up.version)…").font(.caption.weight(.semibold))
          } else {
            Image(systemName: "arrow.down.circle.fill")
            Text("Update available — v\(up.version)").font(.caption.weight(.semibold))
          }
          Spacer(minLength: 4)
          Image(systemName: "chevron.right").font(.caption2)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.green)
      }
      .buttonStyle(.plain).onHover(perform: pointer)
    }
  }

  private func openUpdate() {
    panelWindow?.orderOut(nil)   // collapse the panel so the window takes focus
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "update")
  }
```

- [ ] **Step 3: Add the "Updates" section to Settings**

In `app/Sources/KickbacksBar/SettingsView.swift`, immediately after the `General` section's closing brace (line 68, before the closing `}` of the `Form`), add:

```swift
      Section("Updates") {
        HStack {
          Text("Version")
          Spacer()
          Text(vm.currentVersionString).foregroundStyle(.secondary).monospacedDigit()
        }
        Toggle("Automatically check for updates",
               isOn: Binding(get: { vm.autoCheckUpdates }, set: { vm.setAutoCheckUpdates($0) }))
        Picker("Check every", selection: Binding(get: { vm.updateCheckHours }, set: { vm.setUpdateCheckHours($0) })) {
          Text("6 hours").tag(6)
          Text("12 hours").tag(12)
          Text("Daily").tag(24)
          Text("Weekly").tag(168)
        }.disabled(!vm.autoCheckUpdates)
        Button("Check now") { Task { await vm.checkForUpdates(manual: true) } }
        if let r = vm.updateCheckResult {
          Text(r).font(.caption).foregroundStyle(.secondary)
        }
      }
```

- [ ] **Step 4: Give Settings room for the new section**

In `app/Sources/KickbacksBar/SettingsView.swift`, change the frame (line 71) from:

```swift
    .frame(width: 380, height: 540)
```

to:

```swift
    .frame(width: 380, height: 620)
```

- [ ] **Step 5: Build + full test suite**

Run: `swift build --package-path app && swift test --package-path app`
Expected: **Build complete** and **all tests PASS**.

- [ ] **Step 6: Commit**

```bash
git add app/Sources/KickbacksBar/KickbacksBarApp.swift app/Sources/KickbacksBar/MenuContent.swift app/Sources/KickbacksBar/SettingsView.swift
git commit -m "feat(app): wire updates — window scene, panel banner, Settings section"
```

---

## Task 7: Final verification + manual QA

**Files:** none (verification only)

- [ ] **Step 1: Full clean build + tests**

Run: `swift build --package-path app -c release && swift test --package-path app`
Expected: **Build complete** (release) and **all tests PASS**.

- [ ] **Step 2: Install the built app**

Run: `bash scripts/install-app.sh`
Expected: builds `Kickbacks.app`, drops it in `/Applications`, relaunches. (This is the `.app` install path → the update button will fall back to "Open release page"; that's expected for this path.)

- [ ] **Step 3: Manual QA checklist** (do each, confirm, check the box)

- [ ] Open the panel → Settings → **Updates** section shows the current version (e.g. `0.1.0`), the auto-check toggle (on), the "Check every" picker (Daily), and a **Check now** button.
- [ ] Click **Check now** → since `0.1.0` is current and `0.2.0` will be the latest once released, it reports either "You're up to date" or "Update available: v0.2.0" with no hang. (To force the available path before a real release exists, temporarily set `KICKBACKS_BIN` to a wrapper printing an old version, or test after `v0.2.0` ships.)
- [ ] When an update is available: the green **Update available — v0.2.0** banner appears at the top of the panel; clicking it collapses the panel and opens the Update window with the rendered changelog.
- [ ] In the Update window: **Skip this version** hides the banner and it does not reappear on the next check; **Later** just closes.
- [ ] Toggle **Automatically check for updates** off → the "Check every" picker disables.
- [ ] (Homebrew install only — `brew install` + `kickbacks bar install`) **Update & Restart** streams `brew` output in the window, can be backgrounded via **Continue in background**, and on success the menu-bar app relaunches on the new version (icon blips). On a forced failure (e.g. no network), it shows the log + **Open release page**.

- [ ] **Step 4: Note QA results in the commit (if any fixes were needed)**

If QA surfaced fixes, commit them with a clear message, e.g.:

```bash
git add -A
git commit -m "fix(app): <what QA surfaced>"
```

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| `Updater.currentVersion()` via `kickbacks --version` + Info.plist fallback | Task 2 |
| `Updater.fetchLatest()` anonymous GitHub GET | Task 2 |
| `Updater.isNewer` semver compare (tested) | Task 1 |
| `Updater.installMethod()` / `classify` (tested) | Tasks 1–2 |
| `Release` parse from GitHub JSON (tested) | Task 1 |
| `UpdateRunner` detached `brew upgrade`, streamed log | Task 3 |
| Relaunch via `launchctl kickstart` (+ KeepAlive) / non-agent fallback | Tasks 3–4 |
| MenuVM state, `autoCheckUpdates`, `updateCheckHours`, `skippedVersion`, timer | Task 4 |
| Check on launch + every N hours + manual | Task 4 |
| Panel banner | Task 6 |
| Update window with markdown changelog + Update/Skip/Later | Task 5 |
| Settings "Updates" section (version, toggle, interval, Check now) | Task 6 |
| Non-brew / brew-missing / failure fallbacks → release page | Tasks 4–5 |
| Auto-check failures silent; manual shows inline error | Task 4 |
| Unit tests: isNewer, classify, release decode | Task 1 |

No gaps.

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to". Every code step has complete code; every run step has an exact command + expected result.

**3. Type consistency:** `Release(version/notes/htmlURL/publishedAt)`, `InstallMethod.homebrew(brewPath:)/.appBundle/.unknown`, `UpdateState{idle,checking,available,updating,failed}`, and the method names (`isNewer(_:than:)`, `parseVersion`, `parseRelease`, `classify(executablePath:cliPath:exists:)`, `currentVersion`, `fetchLatest`, `installMethod`, `checkForUpdates(manual:)`, `startUpdate`, `skipUpdate`, `setAutoCheckUpdates`, `setUpdateCheckHours`, `canBrewUpdate`, `UpdateRunner.upgrade(brewPath:onLine:completion:)`/`relaunch`/`barAgentInstalled`) are used identically across tasks. `ModelClient.binaryPath()` is the existing public API reused in Task 2.
