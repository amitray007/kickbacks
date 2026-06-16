# In-app updates for the Kickbacks menu-bar app

- **Date:** 2026-06-16
- **Status:** Design — pending review
- **Scope:** The macOS menu-bar app (`app/`). No backend or CLI behaviour changes beyond reusing `kickbacks --version`.

## Goal

Let the menu-bar app tell the user when a newer Kickbacks release exists, show the
changelog, and — on the user's say-so — update itself by running `brew upgrade` **in the
background** and relaunching, without interrupting whatever the user is doing.

Modelled on Ghostty's update UX (a clear "new version" presentation with release notes and
an explicit choice), but driven by Homebrew instead of Sparkle, because the app is shipped
unsigned and un-notarized.

## Non-goals

- No Sparkle, no appcast, no code-signing/notarization.
- No silent/forced auto-install. The user always decides whether to update.
- No fast in-place binary swap from release zips in v1 (see *Future*).
- No change to the read-only posture toward the Kickbacks backend.

## Background — how the app is installed and run

There are two install paths, and the update story differs per path:

1. **Homebrew (primary).** `brew install kickbacks` compiles from source and installs two
   binaries into brew's `bin`: `kickbacks` (CLI) and `kickbacks-bar` (the menu-bar
   executable). `kickbacks bar install` registers a launchd **GUI agent**
   (`ai.kickbacks.bar`, `KeepAlive` + `RunAtLoad`, `LimitLoadToSessionType=Aqua`) whose
   `ProgramArguments` is the bare `kickbacks-bar` binary. So the running app is **not** a
   `.app` bundle and has **no Info.plist version**. `brew upgrade kickbacks` replaces the
   binary; relaunch is a `launchctl kickstart`.
2. **`scripts/install-app.sh` (secondary).** Builds `/Applications/Kickbacks.app` with an
   Info.plist version injected from `cli/package.json`. `brew upgrade` does **not** touch
   this. For this path the app falls back to "open the release page."

Relevant facts:
- The CLI prints its version: `kickbacks --version` → e.g. `0.1.0` (compiled in from
  `package.json`). Both binaries are built/installed together, so the CLI's version is the
  app's version.
- `ModelClient.binaryPath()` already resolves the `kickbacks` binary (`$KICKBACKS_BIN` →
  sibling of the app executable → `/opt/homebrew/bin` → `/usr/local/bin`). `brew` is a
  sibling of that binary.
- The app is unsigned and **not sandboxed**, so `URLSession` to `api.github.com` needs no
  entitlement, and shelling out to `brew`/`launchctl` is unrestricted.
- `Notifier.swift` (UserNotifications) already exists for cap/milestone alerts and is reused
  here.

## Chosen approach

**Notify + changelog → background `brew upgrade` → relaunch.**

- Version source: `kickbacks --version` (CLI is the source of truth; works for brew + `.app`).
- "Latest version" source: an anonymous read-only `GET` to this project's own GitHub
  release API.
- The update runs **detached in the background** so the multi-minute source build never
  blocks the user; the app relaunches itself when it finishes.

### Rejected alternatives

- **Sparkle self-updater** — requires code-signing + notarization (deliberately avoided) and
  conflicts with a Homebrew-managed install.
- **Fast in-place swap** of the prebuilt `kickbacks-cli-macos.zip` we already publish — fast,
  but desyncs Homebrew's records and needs Gatekeeper-quarantine handling. Deferred.

## Detailed design

### New / touched files

| File | Role |
|---|---|
| `app/Sources/KickbacksKit/Updater.swift` | **new** — version detection, GitHub release fetch, semver compare, install-method detection (mostly pure → unit-tested) |
| `app/Sources/KickbacksBar/UpdateRunner.swift` | **new** — runs `brew upgrade` detached, streams log, relaunches |
| `app/Sources/KickbacksBar/UpdateView.swift` | **new** — the update window (version, date, rendered changelog, actions) |
| `app/Sources/KickbacksBar/MenuVM.swift` | update state + check timer + persisted prefs |
| `app/Sources/KickbacksBar/MenuContent.swift` | slim conditional "Update available" banner |
| `app/Sources/KickbacksBar/SettingsView.swift` | new "Updates" section |
| `app/Sources/KickbacksBar/KickbacksBarApp.swift` | register the Update `Window` scene |
| `app/Tests/KickbacksKitTests/UpdaterTests.swift` | **new** — unit tests for `Updater` |

### `Updater` (KickbacksKit)

```swift
public struct Release: Equatable {
  public let version: String      // normalized, no leading "v" — e.g. "0.2.0"
  public let notes: String        // GitHub release body (markdown)
  public let htmlURL: String
  public let publishedAt: String  // ISO date, for display
}

public enum InstallMethod: Equatable {
  case homebrew(brewPath: String) // can run `brew upgrade`
  case appBundle                  // /Applications/Kickbacks.app — release-page fallback
  case unknown                    // dev / other — release-page fallback
}

public enum Updater {
  /// `kickbacks --version`; falls back to the .app Info.plist; nil if neither is available.
  public static func currentVersion() -> String?

  /// Anonymous GET api.github.com/repos/amitray007/kickbacks/releases/latest.
  /// `/latest` already excludes drafts + prereleases. nil on any failure.
  public static func fetchLatest() async -> Release?

  /// True only when `latest` is strictly greater by numeric semver (leading "v" stripped,
  /// prerelease/build suffix treated as older). Parse failure → false (never a false prompt).
  public static func isNewer(_ latest: String, than current: String) -> Bool

  /// .homebrew if a sibling `brew` exists next to the resolved kickbacks binary (or a brew
  /// prefix is present); .appBundle if running under /Applications/*.app; else .unknown.
  public static func installMethod() -> InstallMethod
}
```

GitHub request specifics: header `Accept: application/vnd.github+json`, a `User-Agent`
(GitHub rejects UA-less requests), no auth token. Handle 403 (rate limit) and 404 (no
releases yet) by returning nil. Anonymous limit is 60/hr/IP; we check ≤ once per configured
interval (hours), far under it.

### `UpdateRunner` (KickbacksBar)

Performs the upgrade for the `.homebrew` case:

1. Resolve `brew` = sibling of the `kickbacks` binary, else `/opt/homebrew/bin/brew`, else
   `/usr/local/bin/brew`.
2. Run `/bin/sh -lc "<brew> update && <brew> upgrade kickbacks"` as a **detached** `Process`
   on a background queue. Merge stdout+stderr and append lines to a `@MainActor @Published
   var log: [String]` so the (optional, non-modal) window can show live progress. The user
   is free to close the window and keep working.
3. On exit status 0 → post a `Notifier` notification ("Updated to vX.Y.Z") and relaunch:
   `launchctl kickstart -k gui/\(getuid())/ai.kickbacks.bar` (immediate swap to the new
   binary; `KeepAlive` would also restart on a bare exit, but kickstart avoids the launchd
   restart-throttle delay). Run the kickstart from a tiny detached `sh` (`sleep 1; …`) so the
   notification is delivered first, then terminate ourselves.
4. On non-zero exit / brew not found → post a failure notification, keep the window's log
   visible, and offer **Open release page**. Never relaunch on failure.

For `.appBundle` / `.unknown`: skip brew entirely; the primary action is **Open release page**.
Edge case: if the bar launchd agent isn't loaded (brew binary run directly), kickstart fails →
fall back to a "Quit and reopen Kickbacks to finish updating" notification.

### State on `MenuVM`

```
@Published var availableUpdate: Release?          // non-nil ⇒ banner shows
@Published var updateState: UpdateState           // .idle / .checking / .available / .updating / .failed
@AppStorage var autoCheckUpdates: Bool = true
@AppStorage var updateCheckHours: Int = 24        // Settings picker
@AppStorage var skippedVersion: String = ""       // "Skip this version"
@Published var lastUpdateCheck: Date?
```

A timer checks on launch (after a short delay so startup isn't slowed) and every
`updateCheckHours`. `check()` is also callable manually from Settings.

### UX flow (non-interfering by design)

1. Background check finds a newer version (and it isn't the skipped one).
2. A slim **"Update available → v0.2.0"** row appears at the top of the panel; a single
   UserNotification fires once per version. Nothing is modal; nothing interrupts.
3. Opening it shows the **Update window**: version + date, the **rendered changelog** (release
   `body` via `AttributedString(markdown:)`), and **Update & Restart · Skip this version ·
   Later**.
4. **Update & Restart** kicks off the background upgrade *immediately* and the window can be
   closed — a small spinner stays on the panel's update row. When the build finishes the app
   relaunches itself (menu-bar relaunch is a near-invisible icon blip; no documents to lose).
   **Skip** suppresses this version; **Later** just dismisses.

```
┌─ Kickbacks — Update ─────────────┐    Settings ▸ Updates
│  v0.2.0  ·  Jun 16              │    ┌──────────────────────────┐
│  ─────────────────────────────  │    │ Version            0.1.0 │
│  • Favicon fallback for ads      │    │ Auto-check         [ ✔ ] │
│  • Share moved to bottom bar     │    │ Check every    [ Daily ▾]│
│  • …(from the GitHub release)    │    │           [ Check now ]  │
│                                  │    └──────────────────────────┘
│  [Update & Restart] [Skip] [Later]│
└──────────────────────────────────┘
```

### Settings — new "Updates" section

- **Version** — current, from `kickbacks --version`.
- **Automatically check for updates** — toggle (default on). Off ⇒ manual-only (via "Check now").
- **Check every** — picker: `6h / 12h / Daily / Weekly`, enabled only when auto-check is on.
- **Check now** — runs a check and reports inline ("You're up to date" / "v0.2.0 available").

## Data flow

```
launch / timer ──▶ Updater.fetchLatest() ──▶ Updater.isNewer(latest, currentVersion())
   │                                              │ yes & ≠ skippedVersion
   ▼ no/failed (silent on auto)                   ▼
   idle                              set availableUpdate ─▶ panel banner + 1 notification
                                                            │ user: Update & Restart
                                                            ▼
                                     UpdateRunner: detached `brew upgrade` (streamed log)
                                                            │ exit 0
                                                            ▼
                                     notify + `launchctl kickstart -k …bar` ─▶ new binary
```

## Error handling

- Auto-check failures are **silent** (no nagging). Manual "Check now" surfaces an inline error.
- Not a brew install → no shell-out; "Open release page."
- brew missing / `upgrade` non-zero → failure notification + visible log + release-page
  fallback; no relaunch.
- GitHub 403/404/parse failure → "couldn't check"; never a false prompt.
- Semver parse failure → `isNewer` returns false.

## Security & privacy

- The only new network call is an **anonymous, read-only `GET`** to *this project's own*
  public GitHub release API — no token, no user data, no third-party telemetry. It reads
  release metadata, never the Kickbacks backend; the read-only posture is unchanged.
- `brew upgrade` runs **only on an explicit click**. We never auto-install, and we never
  download-and-execute arbitrary binaries — Homebrew (the user's own trusted package manager)
  rebuilds from pinned source.
- No new entitlements (app is unsigned + unsandboxed).

## Testing

- **Unit (`Updater`):** `isNewer` — `0.1.0<0.2.0`, equal, `v`-prefix, `0.10.0>0.9.0`,
  prerelease treated as older, malformed → false. `installMethod` path detection. Release
  JSON decode (tag/body/url).
- **Manual:** end-to-end on a brew install (check → window → background upgrade → kickstart
  relaunch comes up on the new version); `.app` fallback opens the release page; offline →
  silent.

## Known tradeoffs & future

- **Compile time:** because the formula builds from source, `brew upgrade` recompiles
  (Swift release build + bun) for ~1–4 min. Mitigated by running detached in the background
  with a live log; the user isn't blocked. Accepted cost of staying unsigned.
- **Future (optional):** a fast path that downloads the already-published
  `kickbacks-cli-macos.zip`, verifies its checksum, swaps the two binaries, and relaunches —
  seconds instead of minutes — at the cost of desyncing brew's records + quarantine handling.
```
