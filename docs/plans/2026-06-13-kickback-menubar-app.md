# Kickback — Plan 4: native Swift menu-bar app

> **For agentic workers:** implement task-by-task. TS work in `cli/` (TDD, `bun test`); Swift work in `app/` (`swift build` / `swift test`). Commit per task on `main`. The menu-bar **display** + launch-at-login are GUI/user-QA — everything else is verified headlessly.

**Goal:** A native macOS `MenuBarExtra` app (design §15.1): title shows today's earnings + a trend arrow (amber when stalled); the dropdown shows lifetime, rate, daily cap + reset + projection, a 24h sparkline, the served ad, and a status line, with Refresh / Open dashboard / Quit. It is a **thin renderer**: it shells out to `kickback model --json` and maps the result onto SwiftUI views — no earnings logic duplicated in Swift.

**Decisions (locked 2026-06-13):**
- **SwiftPM executable** (`app/Package.swift`) — builds/tests headless; Plan 5 wraps the binary in a `.app` for the cask.
- **Data bridge = `kickback model --json`** — a new read/derive command in the TS CLI; Swift spawns it. One model source, thinnest Swift.

**Architecture:** TS adds `model.ts` (`buildMenuModel`, pure) + a `model` command (live fetch with graceful degradation to last-known from the store, then JSON). Swift `app/` is a `MenuBarExtra` app with a `Codable` DTO mirroring the JSON, a `ModelClient` that runs the binary on a timer, and SwiftUI views for the title + dropdown. The two languages share **data via JSON over a process boundary** (the CLI already bridges to the SQLite store).

**Tech:** Bun/TS (existing), Swift 6.3 / SwiftUI `MenuBarExtra` (macOS 13+), `Foundation.Process`.

---

## The bridge contract — `kickback model --json`

A single JSON object (display-ready strings + a `state` enum for coloring). Stable contract between TS and Swift:

```jsonc
{
  "signedIn": true,
  "state": "earning",            // signed-out | killed | cap | stalled | no-serve | earning
  "title": "$0.56 ▴",            // menu-bar title ("kickback" when signed out)
  "today": "$0.56",
  "lifetime": "$12.34",
  "rate": "$0.18/hr",            // "" when rate is 0
  "trend": "up",                 // up | down | flat
  "cap": "$0.56 / $1.00",        // "" when no cap
  "capPct": 56,                  // 0 when no cap
  "resets": "4h12m",             // "" when no cap
  "projection": "~2h26m",        // "" when unknown/at cap
  "spark": "▁▂▃▅▇",              // "" when <2 samples
  "ad": "Inflowpay: Global sales, 50% less fees",  // "" when none
  "adUrl": "https://inflowpay.test",               // "" when none
  "status": "Earning",           // dropdown status line
  "ageSeconds": 4                // age of the data (0 on a fresh fetch)
}
```

`state` precedence: `signed-out` > `killed` > `cap` > `stalled` > `no-serve` > `earning`. `stalled` is derived from the store's recent **poller** samples (`active` + flat `today_usd`); without the poller running it simply won't show (fail-safe).

---

## File Structure

```
cli/
  src/model.ts        # NEW — buildMenuModel(p, e, store, now): MenuModel (pure)
  src/cli.ts          # + `model` command (live fetch → fallback to last-known → JSON)
  test/model.test.ts  # NEW — buildMenuModel cases
app/                  # NEW — SwiftPM executable
  Package.swift
  Sources/KickbackBar/
    KickbackBarApp.swift   # @main MenuBarExtra app (accessory activation)
    Model.swift            # Codable MenuModel DTO + state enum
    ModelClient.swift      # runs `kickback model --json` via Process; finds the binary
    MenuContent.swift      # the dropdown SwiftUI view (design §15.1)
  Tests/KickbackBarTests/
    ModelTests.swift       # JSON decode + a couple of presentation assertions
  README.md
```

---

## Task 1 — `buildMenuModel` + `kickback model --json` (TS)

**Files:** `cli/src/model.ts`, `cli/src/cli.ts`, `cli/test/model.test.ts`.

- [ ] **Step 1: failing test** (`model.test.ts`) — pure builder over fakes + in-memory store:
```ts
import { test, expect } from "bun:test";
import { buildMenuModel } from "../src/model";
import { openStore } from "../src/store";
import type { Portfolio, Earnings } from "../src/types";

const P: Portfolio = { lifetimeUsd: 12.34, todayUsd: 0.56, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "552e20ec", campaignId: "23f8444b", text: "Inflowpay", clickUrl: "https://x.test", bannerEnabled: true }] };
const E: Earnings = { cap: { scope: "daily", capUsd: 1, resetSeconds: 15120 } };

test("buildMenuModel produces display-ready fields", () => {
  const store = openStore(":memory:");
  store.insertSample({ ts: 1, lifetimeUsd: 12.0, todayUsd: 0.50, adId: "x", kill: false });
  const m = buildMenuModel({ p: P, e: E, store, now: 3_600_001, signedIn: true });
  expect(m.signedIn).toBe(true);
  expect(m.today).toBe("$0.56");
  expect(m.lifetime).toBe("$12.34");
  expect(m.title).toContain("$0.56");
  expect(m.cap).toBe("$0.56 / $1.00");
  expect(m.capPct).toBe(56);
  expect(m.resets).toBe("4h12m");
  expect(m.ad).toBe("Inflowpay");
  expect(["earning", "cap", "killed", "no-serve", "stalled"]).toContain(m.state);
});

test("buildMenuModel signed-out shows the brand title", () => {
  const store = openStore(":memory:");
  const m = buildMenuModel({ p: null, e: null, store, now: 1, signedIn: false });
  expect(m.signedIn).toBe(false);
  expect(m.state).toBe("signed-out");
  expect(m.title).toBe("kickback");
});
```

- [ ] **Step 2:** `bun test test/model.test.ts` → FAIL (module not found).
- [ ] **Step 3:** `model.ts` — reuse `derive`/`ui` formatters (no new logic):
```ts
import type { Portfolio, Earnings } from "./types";
import type { Store } from "./store";
import { ratePerHour, projectSecondsToCap, earningState, isStalled, fmtUsd, fmtDuration } from "./derive";
import { sparkline } from "./ui";

export type MenuState = "signed-out" | "killed" | "cap" | "stalled" | "no-serve" | "earning";
export interface MenuModel {
  signedIn: boolean; state: MenuState; title: string;
  today: string; lifetime: string; rate: string; trend: "up" | "down" | "flat";
  cap: string; capPct: number; resets: string; projection: string; spark: string;
  ad: string; adUrl: string; status: string; ageSeconds: number;
}

export interface MenuInput { p: Portfolio | null; e: Earnings | null; store: Store; now: number; signedIn: boolean; }

const STATUS: Record<MenuState, string> = {
  "signed-out": "Signed out", killed: "Killswitch on", cap: "Cap reached",
  stalled: "Stalled — not earning", "no-serve": "No ad serving", earning: "Earning",
};

export function buildMenuModel(i: MenuInput): MenuModel {
  const blank: MenuModel = { signedIn: false, state: "signed-out", title: "kickback",
    today: "$0.00", lifetime: "$0.00", rate: "", trend: "flat", cap: "", capPct: 0, resets: "",
    projection: "", spark: "", ad: "", adUrl: "", status: STATUS["signed-out"], ageSeconds: 0 };
  if (!i.signedIn || !i.p) return blank;

  const p = i.p, e = i.e;
  const samples = i.store.recentSince(i.now - 24 * 3_600_000);
  const rate = ratePerHour(samples.filter((s) => s.ts >= i.now - 6 * 3_600_000));
  const latest = samples[samples.length - 1];
  const prev = samples[samples.length - 2];
  const trend: "up" | "down" | "flat" = !latest || !prev ? (rate > 0 ? "up" : "flat")
    : latest.todayUsd > prev.todayUsd ? "up" : latest.todayUsd < prev.todayUsd ? "down" : "flat";
  const active = latest?.active === true;
  const stalled = isStalled({ samples, now: i.now, windowMs: 10 * 60_000, active });
  const base = earningState(p, e); // killed | cap | no-serve | earning
  const state: MenuState = base === "earning" && stalled ? "stalled" : base;

  const arrow = trend === "up" ? "▴" : trend === "down" ? "▾" : "—";
  const cap = e?.cap ?? null;
  const eta = cap ? projectSecondsToCap(p.todayUsd, cap.capUsd, rate) : null;
  const ad = p.ads[0];
  return {
    signedIn: true, state,
    title: `${fmtUsd(p.todayUsd)} ${arrow}`,
    today: fmtUsd(p.todayUsd), lifetime: fmtUsd(p.lifetimeUsd),
    rate: rate > 0 ? `${fmtUsd(rate)}/hr` : "", trend,
    cap: cap ? `${fmtUsd(p.todayUsd)} / ${fmtUsd(cap.capUsd)}` : "",
    capPct: cap && cap.capUsd > 0 ? Math.min(100, Math.round((p.todayUsd / cap.capUsd) * 100)) : 0,
    resets: cap ? fmtDuration(cap.resetSeconds) : "",
    projection: eta !== null && eta > 0 ? `~${fmtDuration(eta)}` : "",
    spark: samples.length >= 2 ? sparkline(samples.map((s) => s.todayUsd)) : "",
    ad: ad?.text ?? "", adUrl: ad?.clickUrl ?? "",
    status: STATUS[state],
    ageSeconds: latest ? Math.max(0, Math.round((i.now - latest.ts) / 1000)) : 0,
  };
}
```

- [ ] **Step 4:** `bun test test/model.test.ts` → PASS.
- [ ] **Step 5:** wire `cli.ts` — `model` command: live fetch (records a sample, like portfolio), degrade to last-known on failure, print JSON:
```ts
import { buildMenuModel } from "./model";

async function cmdModel() {
  const signedIn = !!loadTokens();
  const store = openStore(DB_FILE);
  const now = Date.now();
  try {
    let p = null, e = null;
    if (signedIn) {
      try {
        p = await runAuthed((tk) => fetchPortfolio(deps(tk)));
        e = await runAuthed((tk) => fetchEarnings(deps(tk))).catch(() => null);
        recordSample(store, p); // contributes to history while the menu is open
      } catch { /* network/API down → fall through to last-known */ }
    }
    console.log(JSON.stringify(buildMenuModel({ p, e, store, now, signedIn })));
  } finally { store.close(); }
}
```
Register `model: cmdModel` in the table + usage. (`recordSample` already exists; note it only records when the live fetch succeeded.)

- [ ] **Step 6:** `bun test` (full) + `tsc` green. Manual: `KICKBACK_CONFIG_DIR=/tmp/x bun run src/cli.ts model` (signed out) → prints `{"signedIn":false,...,"title":"kickback"}`. Commit `feat(model): kickback model --json bridge for the menu-bar app`.

---

## Task 2 — Swift package scaffold + `Model` DTO + decode test

**Files:** `app/Package.swift`, `app/Sources/KickbackBar/Model.swift`, `app/Tests/KickbackBarTests/ModelTests.swift`.

- [ ] **Step 1:** `app/Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "KickbackBar",
  platforms: [.macOS(.v13)],
  targets: [
    .executableTarget(name: "KickbackBar"),
    .testTarget(name: "KickbackBarTests", dependencies: ["KickbackBar"]),
  ]
)
```

- [ ] **Step 2:** `Model.swift` — Codable DTO mirroring the JSON contract:
```swift
import Foundation

enum MenuState: String, Codable { case signedOut = "signed-out", killed, cap, stalled, noServe = "no-serve", earning }

struct MenuModel: Codable, Equatable {
  var signedIn: Bool
  var state: MenuState
  var title: String
  var today, lifetime, rate, trend, cap: String
  var capPct: Int
  var resets, projection, spark, ad, adUrl, status: String
  var ageSeconds: Int

  static let signedOut = MenuModel(signedIn: false, state: .signedOut, title: "kickback",
    today: "$0.00", lifetime: "$0.00", rate: "", trend: "flat", cap: "", capPct: 0,
    resets: "", projection: "", spark: "", ad: "", adUrl: "", status: "Signed out", ageSeconds: 0)

  static func decode(_ data: Data) -> MenuModel? { try? JSONDecoder().decode(MenuModel.self, from: data) }
}
```

- [ ] **Step 3:** `ModelTests.swift` — decode the exact TS JSON shape:
```swift
import XCTest
@testable import KickbackBar

final class ModelTests: XCTestCase {
  func testDecodesEarningModel() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$0.56 ▴","today":"$0.56","lifetime":"$12.34","rate":"$0.18/hr","trend":"up","cap":"$0.56 / $1.00","capPct":56,"resets":"4h12m","projection":"~2h26m","spark":"▁▂▃","ad":"Inflowpay","adUrl":"https://x.test","status":"Earning","ageSeconds":4}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertTrue(m.signedIn); XCTAssertEqual(m.state, .earning)
    XCTAssertEqual(m.today, "$0.56"); XCTAssertEqual(m.capPct, 56)
  }
  func testDecodesSignedOut() throws {
    let m = try XCTUnwrap(MenuModel.decode(Data(#"{"signedIn":false,"state":"signed-out","title":"kickback","today":"$0.00","lifetime":"$0.00","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"","adUrl":"","status":"Signed out","ageSeconds":0}"#.utf8)))
    XCTAssertEqual(m.state, .signedOut); XCTAssertEqual(m.title, "kickback")
  }
}
```

- [ ] **Step 4:** `cd app && swift test` → PASS. Commit `feat(app): Swift package + MenuModel DTO (decode-tested)`.

---

## Task 3 — `ModelClient` (run the CLI, parse)

**Files:** `app/Sources/KickbackBar/ModelClient.swift`.

- [ ] **Step 1:** locate the binary (`KICKBACK_BIN` env, else PATH, else common brew paths) and run `model`:
```swift
import Foundation

enum ModelClient {
  /// Resolve the kickback binary: $KICKBACK_BIN, then PATH, then brew defaults.
  static func binaryPath() -> String? {
    if let b = ProcessInfo.processInfo.environment["KICKBACK_BIN"], !b.isEmpty { return b }
    for p in ["/opt/homebrew/bin/kickback", "/usr/local/bin/kickback"] where FileManager.default.isExecutableFile(atPath: p) { return p }
    return nil
  }

  /// Run `kickback model` and decode. Returns signedOut on any failure (UI stays alive).
  static func fetch() -> MenuModel {
    guard let bin = binaryPath() else { return .signedOut }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["model"]
    let out = Pipe(); proc.standardOutput = out; proc.standardError = Pipe()
    do { try proc.run() } catch { return .signedOut }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return MenuModel.decode(data) ?? .signedOut
  }
}
```

- [ ] **Step 2:** `swift build` → compiles. Commit `feat(app): ModelClient runs `kickback model``.

---

## Task 4 — MenuBarExtra UI (title + dropdown)

**Files:** `app/Sources/KickbackBar/KickbackBarApp.swift`, `app/Sources/KickbackBar/MenuContent.swift`.

- [ ] **Step 1:** `KickbackBarApp.swift` — `MenuBarExtra` with the title + a poll timer:
```swift
import SwiftUI

@main
struct KickbackBarApp: App {
  @StateObject private var vm = MenuVM()
  var body: some Scene {
    MenuBarExtra { MenuContent(vm: vm) } label: { Text(vm.model.title) }
      .menuBarExtraStyle(.window)
  }
}

@MainActor final class MenuVM: ObservableObject {
  @Published var model: MenuModel = .signedOut
  private var timer: Timer?
  init() { refresh(); timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() } }
  func refresh() { Task.detached { let m = ModelClient.fetch(); await MainActor.run { self.model = m } } }
}
```

- [ ] **Step 2:** `MenuContent.swift` — the dropdown (design §15.1), rows hidden when their string is empty:
```swift
import SwiftUI

struct MenuContent: View {
  @ObservedObject var vm: MenuVM
  var m: MenuModel { vm.model }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack { Text("Kickback").bold(); Spacer(); Text(m.status).foregroundStyle(color) }
      Divider()
      row("Today", m.today); row("Lifetime", m.lifetime)
      if !m.rate.isEmpty { row("Rate", "\(m.rate) \(m.trend == "up" ? "▴" : m.trend == "down" ? "▾" : "—")") }
      if !m.spark.isEmpty { row("Last 24h", m.spark) }
      if !m.cap.isEmpty { Divider(); row("Daily cap", "\(m.cap)  (\(m.capPct)%)"); if !m.resets.isEmpty { row("Resets in", m.resets) }; if !m.projection.isEmpty { row("Hits cap", m.projection) } }
      if !m.ad.isEmpty { Divider(); Text("Now showing").foregroundStyle(.secondary)
        Button(action: openAd) { Text(m.ad).lineLimit(1) }.buttonStyle(.link) }
      Divider()
      HStack { Button("Refresh") { vm.refresh() }; Spacer(); Button("Quit") { NSApplication.shared.terminate(nil) } }
    }.padding(12).frame(width: 320)
  }
  private var color: Color { switch m.state { case .earning: .green; case .stalled, .cap: .orange; case .killed: .red; default: .secondary } }
  private func row(_ k: String, _ v: String) -> some View { HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) } }
  private func openAd() { if let u = URL(string: m.adUrl), !m.adUrl.isEmpty { NSWorkspace.shared.open(u) } }
}
```

- [ ] **Step 3:** `swift build` → compiles. Commit `feat(app): MenuBarExtra title + dropdown (design §15.1)`.

---

## Task 5 — Accessory activation + build smoke + README

**Files:** `app/Sources/KickbackBar/KickbackBarApp.swift` (accessory policy), `app/README.md`.

- [ ] **Step 1:** make it a menu-bar-only (no dock icon) app — add an `AppDelegate` setting `NSApp.setActivationPolicy(.accessory)` via `@NSApplicationDelegateAdaptor`, or set `LSUIElement` in the bundled Info.plist (Plan 5). For the SwiftPM run, the adaptor approach:
```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ n: Notification) { NSApp.setActivationPolicy(.accessory) }
}
// in App: @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
```
- [ ] **Step 2:** `cd app && swift build -c release` → produces `.build/release/KickbackBar`. (Run is GUI-only — user QA.)
- [ ] **Step 3:** `app/README.md` — how to build/run (`swift run`), `KICKBACK_BIN` override, and that the dropdown reflects `kickback model`.
- [ ] **Step 4:** commit `feat(app): accessory (menu-bar-only) activation + build`.

---

## Task 6 — Review, docs, QA handoff

- [ ] `bun test` + `tsc` green; `cd app && swift build && swift test` green.
- [ ] compound-engineering review over `model.ts` + cli `model` wiring (TS reviewer). Triage + apply. (Swift is small + GUI; lean on swift build/test.)
- [ ] README (root): mark Plan 4; document `app/` build. design.md: note menu app shipped.
- [ ] **Manual GUI QA (user):** `cd app && KICKBACK_BIN=<path-to-kickback-or-"bun run …"> swift run` → a menu-bar item appears showing today's earnings; dropdown matches §15.1; Refresh updates; clicking the ad opens the URL; amber when stalled (with the poller running). Then Plan 5 bundles it into a signed `.app` + cask.

---

## Self-Review

**Spec coverage (design §15.1):** title = today + trend arrow ✅; amber-on-stall ✅ (state `stalled` → orange); dropdown lifetime/rate/cap/reset/projection/sparkline/ad/status ✅; Refresh/Quit/Open-ad ✅; menu-bar-only ✅ (accessory). "Open dashboard ⌘D" (launch the TUI) — deferred to Plan 5 polish (needs the installed binary + a terminal).
**Headless-testable:** `buildMenuModel` (TS unit) + `MenuModel` decode (swift test) + `swift build`. Only the live MenuBarExtra render + timer are GUI/user-QA.
**DRY:** all earnings logic stays in TS (`model.ts` reuses derive/ui); Swift maps strings → views. The JSON contract is the single coupling point.
**Degradation (design §7):** `model` falls back to last-known store data when the network/API is down; the app shows signed-out (never crashes) on any spawn/parse failure.
