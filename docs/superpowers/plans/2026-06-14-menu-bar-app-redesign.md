# Menu-bar App Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the `KickbacksBar` menu-bar app into a real signed-out → login → data experience with a `K$ <value>` menu-bar label, a full set of states, and a History window — fed by new CLI JSON.

**Architecture:** The CLI (`kickbacks`, TypeScript/Bun) stays the single source of truth: it gains a `history` JSON command and extra `model` fields, with all logic in pure, unit-tested functions. The Swift app (`KickbacksKit` + `KickbacksBar`) renders that JSON and owns only view/auth state — a login flow that spawns `kickbacks login` in the background and polls until signed in, plus a History window.

**Tech Stack:** Bun + TypeScript (`bun test`), `bun:sqlite`; Swift 6 / SwiftUI `MenuBarExtra` + a `Window` scene (`swift build`/`swift test`, XCTest).

**Spec:** `docs/superpowers/specs/2026-06-14-menu-bar-app-redesign-design.md`

**Conventions:**
- Run CLI tests from `cli/` (`cd cli && bun test`). Run Swift from `app/` (`cd app && swift build` / `swift test`).
- Every commit command below omits, for brevity, a trailing `-m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"` — append it to each commit.
- Branding: render `K$` as plain text only. Do not add or reproduce Kickbacks' logo artwork; the app icon stays the existing `app/Resources/AppIcon.*`.

---

## Phase 1 — CLI data layer (TypeScript, TDD)

### Task 1: `localDayKey` + `dailyBuckets`

**Files:**
- Create: `cli/src/history.ts`
- Test: `cli/test/history.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// cli/test/history.test.ts
import { test, expect } from "bun:test";
import { localDayKey, dailyBuckets } from "../src/history";
import type { Sample } from "../src/types";

// noon-local on a given Y/M/D (month is 1-based here for readability)
const day = (y: number, m: number, d: number, h = 12): number => new Date(y, m - 1, d, h).getTime();
const s = (ts: number, todayUsd: number, over: Partial<Sample> = {}): Sample =>
  ({ ts, todayUsd, lifetimeUsd: todayUsd, adId: "a", kill: false, ...over });

test("localDayKey is the local Y-M-D", () => {
  expect(localDayKey(day(2026, 6, 9, 1))).toBe("2026-06-09");
  expect(localDayKey(day(2026, 6, 9, 23))).toBe("2026-06-09");
});

test("dailyBuckets: one bucket per local day, usd = max today_usd that day", () => {
  const samples = [
    s(day(2026, 6, 9, 9), 2), s(day(2026, 6, 9, 17), 5),   // day 1 peaks at 5
    s(day(2026, 6, 10, 10), 3),                            // day 2 peaks at 3
  ];
  const b = dailyBuckets(samples);
  expect(b.map((x) => x.date)).toEqual(["2026-06-09", "2026-06-10"]);
  expect(b.map((x) => x.usd)).toEqual([5, 3]);
});

test("dailyBuckets: hitCap when a sample reached its cap that day", () => {
  const samples = [
    s(day(2026, 6, 9, 9), 1, { capUsd: 2 }),
    s(day(2026, 6, 9, 18), 2, { capUsd: 2 }),  // reached cap
  ];
  expect(dailyBuckets(samples)[0]!.hitCap).toBe(true);
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd cli && bun test test/history.test.ts`
Expected: FAIL — `Cannot find module "../src/history"`.

- [ ] **Step 3: Implement `localDayKey` + `dailyBuckets`**

```ts
// cli/src/history.ts
import type { Sample } from "./types";

export interface DayBucket { date: string; usd: number; hitCap: boolean }
export interface BestDay { date: string; usd: number }

/** Local-day key "YYYY-MM-DD" for a unix-ms timestamp. */
export function localDayKey(ts: number): string {
  const d = new Date(ts);
  const mm = `${d.getMonth() + 1}`.padStart(2, "0");
  const dd = `${d.getDate()}`.padStart(2, "0");
  return `${d.getFullYear()}-${mm}-${dd}`;
}

/** Per-local-day earnings. A day's earnings = max today_usd that day (today_usd
 *  resets at local midnight). hitCap = any sample that day at/above its cap.
 *  Sorted by date ascending. */
export function dailyBuckets(samples: Sample[]): DayBucket[] {
  const by = new Map<string, { usd: number; hitCap: boolean }>();
  for (const s of samples) {
    const k = localDayKey(s.ts);
    const cur = by.get(k) ?? { usd: 0, hitCap: false };
    cur.usd = Math.max(cur.usd, s.todayUsd);
    if (s.capUsd != null && s.capUsd > 0 && s.todayUsd >= s.capUsd) cur.hitCap = true;
    by.set(k, cur);
  }
  return [...by.entries()]
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([date, v]) => ({ date, usd: v.usd, hitCap: v.hitCap }));
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `cd cli && bun test test/history.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd cli && git add src/history.ts test/history.test.ts
git commit -m "feat(history): localDayKey + dailyBuckets derivation"
```

### Task 2: `summarize`

**Files:**
- Modify: `cli/src/history.ts`
- Test: `cli/test/history.test.ts`

- [ ] **Step 1: Add failing tests**

```ts
// append to cli/test/history.test.ts
import { summarize } from "../src/history";

test("summarize: best day, average, and rolling week/month windows", () => {
  const now = day(2026, 6, 30, 12);
  const buckets = [
    { date: "2026-06-01", usd: 4, hitCap: false },   // >7 and <=30 days ago
    { date: "2026-06-28", usd: 10, hitCap: false },  // within 7
    { date: "2026-06-30", usd: 6, hitCap: false },   // today, within 7
  ];
  const sum = summarize(buckets, now);
  expect(sum.daysTracked).toBe(3);
  expect(sum.bestDay).toEqual({ date: "2026-06-28", usd: 10 });
  expect(sum.avgPerDayUsd).toBeCloseTo((4 + 10 + 6) / 3, 5);
  expect(sum.thisWeekUsd).toBe(16);    // 10 + 6
  expect(sum.thisMonthUsd).toBe(20);   // 4 + 10 + 6
});

test("summarize: empty input", () => {
  const sum = summarize([], day(2026, 6, 30));
  expect(sum.daysTracked).toBe(0);
  expect(sum.bestDay).toBeNull();
  expect(sum.avgPerDayUsd).toBe(0);
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd cli && bun test test/history.test.ts`
Expected: FAIL — `summarize is not a function` / not exported.

- [ ] **Step 3: Implement `summarize`**

```ts
// append to cli/src/history.ts
export interface Summary {
  thisWeekUsd: number; thisMonthUsd: number; bestDay: BestDay | null;
  avgPerDayUsd: number; daysTracked: number;
}

/** Rolling windows: thisWeek = last 7 local days incl. today, thisMonth = last 30. */
export function summarize(daily: DayBucket[], now: number): Summary {
  const daysTracked = daily.length;
  const bestDay = daily.reduce<BestDay | null>(
    (b, d) => (!b || d.usd > b.usd ? { date: d.date, usd: d.usd } : b), null);
  const total = daily.reduce((a, d) => a + d.usd, 0);
  const avgPerDayUsd = daysTracked > 0 ? total / daysTracked : 0;
  const lastNDays = (n: number): Set<string> => {
    const set = new Set<string>();
    for (let i = 0; i < n; i++) set.add(localDayKey(now - i * 86_400_000));
    return set;
  };
  const week = lastNDays(7), month = lastNDays(30);
  const sumIn = (set: Set<string>) => daily.filter((d) => set.has(d.date)).reduce((a, d) => a + d.usd, 0);
  return { thisWeekUsd: sumIn(week), thisMonthUsd: sumIn(month), bestDay, avgPerDayUsd, daysTracked };
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `cd cli && bun test test/history.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd cli && git add src/history.ts test/history.test.ts
git commit -m "feat(history): summarize (best/avg/rolling week+month)"
```

### Task 3: `lastEarnedAgoSeconds`

**Files:**
- Modify: `cli/src/history.ts`
- Test: `cli/test/history.test.ts`

- [ ] **Step 1: Add failing tests**

```ts
// append to cli/test/history.test.ts
import { lastEarnedAgoSeconds } from "../src/history";

test("lastEarnedAgoSeconds: time since today_usd last increased", () => {
  const now = 1_000_000;
  const samples = [
    s(now - 600_000, 1.0), // -10m
    s(now - 300_000, 1.5), // -5m  earned
    s(now - 60_000, 1.5),  // -1m  flat
  ];
  expect(lastEarnedAgoSeconds(samples, now)).toBe(300); // last increase was 5m ago
});

test("lastEarnedAgoSeconds: null when never increased", () => {
  const now = 1_000_000;
  expect(lastEarnedAgoSeconds([s(now - 60_000, 2), s(now, 2)], now)).toBeNull();
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd cli && bun test test/history.test.ts`
Expected: FAIL — `lastEarnedAgoSeconds is not a function`.

- [ ] **Step 3: Implement**

```ts
// append to cli/src/history.ts
/** Seconds since today_usd last increased (an earning event), or null if never. */
export function lastEarnedAgoSeconds(samples: Sample[], now: number): number | null {
  const sorted = [...samples].sort((a, b) => a.ts - b.ts);
  let lastTs: number | null = null;
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i]!.todayUsd > sorted[i - 1]!.todayUsd) lastTs = sorted[i]!.ts;
  }
  return lastTs == null ? null : Math.max(0, Math.round((now - lastTs) / 1000));
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `cd cli && bun test test/history.test.ts`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
cd cli && git add src/history.ts test/history.test.ts
git commit -m "feat(history): lastEarnedAgoSeconds"
```

### Task 4: `buildHistory` + `kickbacks history` command

**Files:**
- Modify: `cli/src/history.ts`
- Modify: `cli/src/cli.ts` (imports at top; add `cmdHistory`; register in the command `table` near line 208 and the usage string at line 213)
- Test: `cli/test/history.test.ts`

- [ ] **Step 1: Add a failing test for `buildHistory`**

```ts
// append to cli/test/history.test.ts
import { buildHistory } from "../src/history";
import { openStore } from "../src/store";

test("buildHistory assembles JSON from the store", () => {
  const store = openStore(":memory:");
  store.insertSample({ ts: day(2026, 6, 9, 9), lifetimeUsd: 100, todayUsd: 2, adId: "x", kill: false });
  store.insertSample({ ts: day(2026, 6, 9, 18), lifetimeUsd: 103, todayUsd: 5, adId: "y", kill: false });
  const h = buildHistory(store, day(2026, 6, 9, 20));
  expect(h.daysTracked).toBe(1);
  expect(h.lifetimeUsd).toBe(103);
  expect(h.sinceInstallUsd).toBe(3);            // 103 - 100
  expect(h.daily[0]!.usd).toBe(5);
  expect(h.campaignsSeen).toBe(2);              // ad ids x,y
  expect(h.bestDay).toEqual({ date: "2026-06-09", usd: 5 });
});

test("buildHistory on an empty store is the day-one shape", () => {
  const h = buildHistory(openStore(":memory:"), day(2026, 6, 9, 20));
  expect(h.daysTracked).toBe(0);
  expect(h.daily).toEqual([]);
  expect(h.lifetimeUsd).toBe(0);
  expect(h.bestDay).toBeNull();
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd cli && bun test test/history.test.ts`
Expected: FAIL — `buildHistory is not a function`.

- [ ] **Step 3: Implement `buildHistory`**

```ts
// append to cli/src/history.ts
import type { Store } from "./store";

export interface HistoryJson extends Summary {
  lifetimeUsd: number;
  sinceInstallUsd: number;
  firstSampleTs: number | null;
  daily: DayBucket[];
  capHitsLast7: number;
  campaignsSeen: number;
  activeHours: number;
}

export function buildHistory(store: Store, now: number): HistoryJson {
  const samples = [...store.recentSince(0)].sort((a, b) => a.ts - b.ts);
  const daily = dailyBuckets(samples);
  const sum = summarize(daily, now);
  const first = samples[0] ?? null;
  const last = samples[samples.length - 1] ?? null;
  const lifetimeUsd = last?.lifetimeUsd ?? 0;
  const sinceInstallUsd = first && last ? Math.max(0, last.lifetimeUsd - first.lifetimeUsd) : 0;

  const week = new Set<string>();
  for (let i = 0; i < 7; i++) week.add(localDayKey(now - i * 86_400_000));
  const capHitsLast7 = daily.filter((d) => d.hitCap && week.has(d.date)).length;
  const campaignsSeen = new Set(samples.map((s) => s.adId).filter((a) => a !== "")).size;

  // active hours: sum gaps that follow an active sample, ignoring gaps > 30m (app/poller was off)
  let activeMs = 0;
  for (let i = 1; i < samples.length; i++) {
    if (samples[i - 1]!.active === true) {
      const gap = samples[i]!.ts - samples[i - 1]!.ts;
      if (gap > 0 && gap < 30 * 60_000) activeMs += gap;
    }
  }
  const activeHours = Math.round((activeMs / 3_600_000) * 10) / 10;

  return { ...sum, lifetimeUsd, sinceInstallUsd, firstSampleTs: first?.ts ?? null, daily, capHitsLast7, campaignsSeen, activeHours };
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `cd cli && bun test test/history.test.ts`
Expected: PASS (9 tests).

- [ ] **Step 5: Wire the `history` command into the CLI**

In `cli/src/cli.ts`, add to the existing import from `./store` nothing new (already imports `openStore`). Add this import near the other `./` imports (after the `buildMenuModel` import at line 14):

```ts
import { buildHistory } from "./history";
```

Add this function (next to `cmdModel`):

```ts
// Emit the local earnings history as JSON for the menu-bar app's History window.
// Read-only; works signed-in or out (it only reads the local SQLite history).
function cmdHistory() {
  const store = openStore(DB_FILE);
  try { console.log(JSON.stringify(buildHistory(store, Date.now()))); }
  finally { store.close(); }
}
```

In the `table` object (line ~208) add `history: cmdHistory,` and update the usage string (line ~213) to include `| history`:

```ts
const table: Record<string, () => unknown> = {
  login: cmdLogin, portfolio: cmdPortfolio, watch: cmdWatch, earnings: cmdEarnings,
  raw: cmdRaw, status: cmdStatus, logout: cmdLogout, poll: cmdPoll, poller: cmdPoller,
  model: cmdModel, history: cmdHistory, bar: cmdBar,
};
```

- [ ] **Step 6: Verify the command runs and emits JSON**

Run: `cd cli && bun run src/cli.ts history`
Expected: a single line of JSON, e.g. `{"thisWeekUsd":0,...,"daysTracked":0,"daily":[],"lifetimeUsd":0,...}` (empty-store shape on a fresh DB).

- [ ] **Step 7: Commit**

```bash
cd cli && git add src/history.ts src/cli.ts test/history.test.ts
git commit -m "feat(history): buildHistory + 'kickbacks history' JSON command"
```

### Task 5: Extend `buildMenuModel` (menuValue, ads, threshold, lastEarned, collecting)

**Files:**
- Modify: `cli/src/model.ts` (the `MenuModel` interface ~lines 8-25; both return objects in `buildMenuModel` ~lines 44-83)
- Test: `cli/test/model.test.ts`

- [ ] **Step 1: Add failing tests**

```ts
// append to cli/test/model.test.ts
import { lastEarnedAgoSeconds } from "../src/history"; // ensure history is importable from model side too

test("buildMenuModel adds menuValue, ads, threshold, collecting", () => {
  const store = openStore(":memory:");
  // one sample only → collecting (need >=2 for a trend)
  store.insertSample({ ts: 1, lifetimeUsd: 12.0, todayUsd: 0.5, adId: "x", kill: false });
  const m = buildMenuModel({ p: P, e: E, store, now: 3_600_001, signedIn: true });
  expect(m.menuValue).toBe("0.56");                 // today without the "$"
  expect(m.viewThresholdSeconds).toBe(15);
  expect(m.ads).toEqual([{ text: "Inflowpay", url: "https://x.test" }]);
  expect(m.collecting).toBe(true);                  // <2 samples
});

test("buildMenuModel signed-out menuValue is the dash", () => {
  const store = openStore(":memory:");
  const m = buildMenuModel({ p: null, e: null, store, now: 1, signedIn: false });
  expect(m.menuValue).toBe("—");
  expect(m.ads).toEqual([]);
  expect(m.collecting).toBe(false);
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd cli && bun test test/model.test.ts`
Expected: FAIL — `m.menuValue` is undefined (property doesn't exist).

- [ ] **Step 3: Extend the interface + import**

In `cli/src/model.ts`, change the import on line 3-4 area to also import `lastEarnedAgoSeconds`:

```ts
import { ratePerHour, projectSecondsToCap, earningState, isStalled, fmtUsd, fmtDuration } from "./derive";
import { lastEarnedAgoSeconds } from "./history";
```

Add these fields to the `MenuModel` interface (after `ageSeconds: number;`):

```ts
  menuValue: string;
  viewThresholdSeconds: number | null;
  ads: { text: string; url: string }[];
  lastEarnedAgoSeconds: number | null;
  collecting: boolean;
```

- [ ] **Step 4: Populate both return objects**

In the signed-out return (the `if (!i.signedIn || !i.p)` block), add before the closing `}`:

```ts
      menuValue: "—", viewThresholdSeconds: null, ads: [], lastEarnedAgoSeconds: null, collecting: false,
```

In the signed-in return object (the final `return { ... }`), add these fields (alongside the existing ones):

```ts
    menuValue: p.todayUsd.toFixed(2),
    viewThresholdSeconds: p.viewThresholdSeconds,
    ads: p.ads.map((a) => ({ text: a.text, url: a.clickUrl })),
    lastEarnedAgoSeconds: lastEarnedAgoSeconds(samples, i.now),
    collecting: samples.length < 2,
```

- [ ] **Step 5: Run it, verify it passes**

Run: `cd cli && bun test test/model.test.ts`
Expected: PASS (all model tests, incl. the 2 new).

- [ ] **Step 6: Full CLI test + typecheck**

Run: `cd cli && bunx --bun tsc --noEmit && bun test`
Expected: tsc clean; all tests pass.

- [ ] **Step 7: Commit**

```bash
cd cli && git add src/model.ts test/model.test.ts
git commit -m "feat(model): menuValue, ads, viewThreshold, lastEarned, collecting"
```

---

## Phase 2 — KickbacksKit DTOs (Swift, TDD)

### Task 6: MenuModel additions + AdItem

**Files:**
- Modify: `app/Sources/KickbacksKit/Model.swift`
- Test: `app/Tests/KickbacksKitTests/ModelTests.swift`

- [ ] **Step 1: Update the existing decode tests to the new JSON shape (they will fail to compile/decode)**

Replace the two JSON literals in `ModelTests.swift` so they include the new fields, and add assertions:

```swift
  func testDecodesEarningModel() throws {
    let json = #"{"signedIn":true,"state":"earning","title":"$0.56 ▴","today":"$0.56","lifetime":"$12.34","rate":"$0.18/hr","trend":"up","cap":"$0.56 / $1.00","capPct":56,"resets":"4h12m","projection":"~2h26m","spark":"▁▂▃","ad":"Inflowpay","adUrl":"https://x.test","status":"Earning","ageSeconds":4,"menuValue":"0.56","viewThresholdSeconds":15,"ads":[{"text":"Inflowpay","url":"https://x.test"}],"lastEarnedAgoSeconds":120,"collecting":false}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.menuValue, "0.56")
    XCTAssertEqual(m.ads.first?.text, "Inflowpay")
    XCTAssertEqual(m.viewThresholdSeconds, 15)
    XCTAssertFalse(m.collecting)
  }

  func testDecodesSignedOut() throws {
    let json = #"{"signedIn":false,"state":"signed-out","title":"kickbacks","today":"$0.00","lifetime":"$0.00","rate":"","trend":"flat","cap":"","capPct":0,"resets":"","projection":"","spark":"","ad":"","adUrl":"","status":"Signed out","ageSeconds":0,"menuValue":"—","viewThresholdSeconds":null,"ads":[],"lastEarnedAgoSeconds":null,"collecting":false}"#
    let m = try XCTUnwrap(MenuModel.decode(Data(json.utf8)))
    XCTAssertEqual(m.state, .signedOut)
    XCTAssertEqual(m.menuValue, "—")
    XCTAssertNil(m.viewThresholdSeconds)
  }
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd app && swift test --filter KickbacksKitTests.ModelTests`
Expected: FAIL — `value of type 'MenuModel' has no member 'menuValue'` (compile error).

- [ ] **Step 3: Add `AdItem` + fields to `MenuModel`**

In `app/Sources/KickbacksKit/Model.swift`, add the struct above `MenuModel`:

```swift
public struct AdItem: Codable, Equatable, Sendable {
  public var text: String
  public var url: String
}
```

Add these stored properties to `MenuModel` (after `public var ageSeconds: Int`):

```swift
  public var menuValue: String
  public var viewThresholdSeconds: Int?
  public var ads: [AdItem]
  public var lastEarnedAgoSeconds: Int?
  public var collecting: Bool
```

Update the `signedOut` static so it still compiles (add to its initializer args, after `ageSeconds: 0`):

```swift
    menuValue: "—", viewThresholdSeconds: nil, ads: [], lastEarnedAgoSeconds: nil, collecting: false)
```

(`viewThresholdSeconds` / `lastEarnedAgoSeconds` are `Int?`, so synthesized `Codable` accepts `null`/missing; `ads`, `menuValue`, `collecting` are always emitted by the CLI.)

- [ ] **Step 4: Run it, verify it passes**

Run: `cd app && swift test --filter KickbacksKitTests.ModelTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd app && git add Sources/KickbacksKit/Model.swift Tests/KickbacksKitTests/ModelTests.swift
git commit -m "feat(app): MenuModel gains menuValue/ads/threshold/lastEarned/collecting"
```

### Task 7: HistoryModel DTO

**Files:**
- Create: `app/Sources/KickbacksKit/HistoryModel.swift`
- Test: `app/Tests/KickbacksKitTests/HistoryModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// app/Tests/KickbacksKitTests/HistoryModelTests.swift
import XCTest
@testable import KickbacksKit

final class HistoryModelTests: XCTestCase {
  func testDecodesFull() throws {
    let json = #"{"thisWeekUsd":16,"thisMonthUsd":20,"bestDay":{"date":"2026-06-28","usd":10},"avgPerDayUsd":6.67,"daysTracked":3,"lifetimeUsd":103,"sinceInstallUsd":3,"firstSampleTs":1781000000000,"daily":[{"date":"2026-06-09","usd":5,"hitCap":true}],"capHitsLast7":1,"campaignsSeen":2,"activeHours":1.5}"#
    let h = try XCTUnwrap(HistoryModel.decode(Data(json.utf8)))
    XCTAssertEqual(h.daysTracked, 3)
    XCTAssertEqual(h.bestDay?.usd, 10)
    XCTAssertEqual(h.daily.first?.hitCap, true)
    XCTAssertTrue(h.hasEnough)
    XCTAssertFalse(h.isEmpty)
  }

  func testDecodesEmpty() throws {
    let json = #"{"thisWeekUsd":0,"thisMonthUsd":0,"bestDay":null,"avgPerDayUsd":0,"daysTracked":0,"lifetimeUsd":0,"sinceInstallUsd":0,"firstSampleTs":null,"daily":[],"capHitsLast7":0,"campaignsSeen":0,"activeHours":0}"#
    let h = try XCTUnwrap(HistoryModel.decode(Data(json.utf8)))
    XCTAssertTrue(h.isEmpty)
    XCTAssertFalse(h.hasEnough)
    XCTAssertNil(h.bestDay)
  }
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd app && swift test --filter KickbacksKitTests.HistoryModelTests`
Expected: FAIL — `cannot find 'HistoryModel' in scope`.

- [ ] **Step 3: Implement the DTO**

```swift
// app/Sources/KickbacksKit/HistoryModel.swift
import Foundation

public struct DayBucket: Codable, Equatable, Sendable {
  public var date: String
  public var usd: Double
  public var hitCap: Bool
}

public struct BestDay: Codable, Equatable, Sendable {
  public var date: String
  public var usd: Double
}

/// Decoded from `kickbacks history`. Mirrors HistoryJson in cli/src/history.ts.
public struct HistoryModel: Codable, Equatable, Sendable {
  public var thisWeekUsd: Double
  public var thisMonthUsd: Double
  public var bestDay: BestDay?
  public var avgPerDayUsd: Double
  public var daysTracked: Int
  public var lifetimeUsd: Double
  public var sinceInstallUsd: Double
  public var firstSampleTs: Double?
  public var daily: [DayBucket]
  public var capHitsLast7: Int
  public var campaignsSeen: Int
  public var activeHours: Double

  public var isEmpty: Bool { daysTracked == 0 }
  public var hasEnough: Bool { daysTracked >= 2 }

  public static func decode(_ data: Data) -> HistoryModel? {
    try? JSONDecoder().decode(HistoryModel.self, from: data)
  }
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `cd app && swift test --filter KickbacksKitTests.HistoryModelTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd app && git add Sources/KickbacksKit/HistoryModel.swift Tests/KickbacksKitTests/HistoryModelTests.swift
git commit -m "feat(app): HistoryModel DTO mirroring 'kickbacks history'"
```

### Task 8: MenuPresentation (label + tint, pure & tested)

**Files:**
- Create: `app/Sources/KickbacksKit/MenuPresentation.swift`
- Test: `app/Tests/KickbacksKitTests/MenuPresentationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// app/Tests/KickbacksKitTests/MenuPresentationTests.swift
import XCTest
@testable import KickbacksKit

final class MenuPresentationTests: XCTestCase {
  func testLabel() {
    XCTAssertEqual(MenuPresentation.menuBarLabel(phase: .signedOut, menuValue: "—"), "K$ —")
    XCTAssertEqual(MenuPresentation.menuBarLabel(phase: .signingIn, menuValue: "1.20"), "K$ …")
    XCTAssertEqual(MenuPresentation.menuBarLabel(phase: .signedIn, menuValue: "12.34"), "K$ 12.34")
  }

  func testTint() {
    XCTAssertEqual(MenuPresentation.tint(state: .stalled, phase: .signedIn), .amber)
    XCTAssertEqual(MenuPresentation.tint(state: .cap, phase: .signedIn), .green)
    XCTAssertEqual(MenuPresentation.tint(state: .killed, phase: .signedIn), .red)
    XCTAssertEqual(MenuPresentation.tint(state: .earning, phase: .signedIn), .primary)
    XCTAssertEqual(MenuPresentation.tint(state: .earning, phase: .signingIn), .muted)
  }
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd app && swift test --filter KickbacksKitTests.MenuPresentationTests`
Expected: FAIL — `cannot find 'MenuPresentation' in scope`.

- [ ] **Step 3: Implement**

```swift
// app/Sources/KickbacksKit/MenuPresentation.swift
import Foundation

public enum AuthPhase: Equatable, Sendable { case signedOut, signingIn, signedIn }
public enum MenuTint: String, Equatable, Sendable { case primary, amber, green, red, muted }

/// Pure mapping from (auth phase, earning state) to the menu-bar label string and tint.
public enum MenuPresentation {
  public static func menuBarLabel(phase: AuthPhase, menuValue: String) -> String {
    switch phase {
    case .signingIn: return "K$ …"
    case .signedOut: return "K$ —"
    case .signedIn:  return "K$ \(menuValue)"
    }
  }

  public static func tint(state: MenuState, phase: AuthPhase) -> MenuTint {
    guard phase == .signedIn else { return .muted }
    switch state {
    case .stalled: return .amber
    case .cap:     return .green
    case .killed:  return .red
    case .earning: return .primary
    case .noServe, .signedOut: return .muted
    }
  }
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `cd app && swift test --filter KickbacksKitTests.MenuPresentationTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd app && git add Sources/KickbacksKit/MenuPresentation.swift Tests/KickbacksKitTests/MenuPresentationTests.swift
git commit -m "feat(app): MenuPresentation label + tint mapping"
```

### Task 9: ModelClient — history(), startLogin(), logout()

**Files:**
- Modify: `app/Sources/KickbacksKit/ModelClient.swift`

- [ ] **Step 1: Add the three calls (mirrors the existing `fetch()` spawn pattern)**

Append inside the `ModelClient` enum, after `fetch()`:

```swift
  /// Runs `kickbacks history` and decodes it. nil on any transient failure.
  public static func history() -> HistoryModel? {
    guard let bin = binaryPath() else { return nil }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["history"]
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 { return nil }
    return HistoryModel.decode(data)
  }

  /// Spawns `kickbacks login` in the background (opens the browser + runs the local
  /// callback server). Returns the running process so the caller can cancel it; nil if
  /// no CLI is available. Caller polls `fetch()` for `signedIn` to know it finished.
  public static func startLogin() -> Process? {
    guard let bin = binaryPath() else { return nil }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["login"]
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }
    return proc
  }

  /// Runs `kickbacks logout` and waits for it (revokes the server session + clears tokens).
  public static func logout() {
    guard let bin = binaryPath() else { return }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: bin)
    proc.arguments = ["logout"]
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    try? proc.run()
    proc.waitUntilExit()
  }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd app && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/KickbacksKit/ModelClient.swift
git commit -m "feat(app): ModelClient.history/startLogin/logout"
```

---

## Phase 3 — App: auth state machine, menu bar, panel

### Task 10: MenuVM — auth phase + sign-in/out

**Files:**
- Modify: `app/Sources/KickbacksBar/MenuVM.swift`

- [ ] **Step 1: Replace MenuVM with the auth-aware version**

```swift
// app/Sources/KickbacksBar/MenuVM.swift
import SwiftUI
import KickbacksKit

/// Holds the polled model + a small auth phase machine. Normal polling sets the phase
/// from `model.signedIn`; `signIn()` overrides it with `.signingIn` while the spawned
/// `kickbacks login` runs, polling until the model reports signed-in (or it times out).
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
```

- [ ] **Step 2: Build**

Run: `cd app && swift build`
Expected: `Build complete!` (MenuContent still references old API — if it fails to build, that's expected until Task 11; build again after Task 11. To keep this task self-contained, only verify MenuVM compiles by running `swift build` — known-failing references in MenuContent are fixed next task.)

> Note: Steps 2 here may not fully build until Task 11 lands (MenuContent uses the VM). Land Task 11 before the Phase-3 build check.

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/KickbacksBar/MenuVM.swift
git commit -m "feat(app): MenuVM auth phase + background-spawn sign-in/out"
```

### Task 11: MenuContent — all states + menu-bar label

**Files:**
- Modify: `app/Sources/KickbacksBar/MenuContent.swift`
- Modify: `app/Sources/KickbacksBar/KickbacksBarApp.swift`

- [ ] **Step 1: Rewrite MenuContent to render every state**

```swift
// app/Sources/KickbacksBar/MenuContent.swift
import SwiftUI
import AppKit
import KickbacksKit

struct MenuContent: View {
  @ObservedObject var vm: MenuVM
  @Environment(\.openWindow) private var openWindow
  private var m: MenuModel { vm.model }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      Divider()
      switch vm.phase {
      case .signedOut: signedOut
      case .signingIn: signingIn
      case .signedIn:  signedIn
      }
    }
    .padding(12)
    .frame(width: 300)
  }

  private var header: some View {
    HStack {
      (Text("K$ ").foregroundStyle(.green).bold() + Text("Kickbacks").bold())
      Spacer()
      if vm.phase == .signedIn {
        HStack(spacing: 5) {
          Circle().fill(dotColor).frame(width: 8, height: 8)
          Text(m.status).foregroundStyle(.secondary).font(.caption)
        }
      }
    }
  }

  // MARK: states

  private var signedOut: some View {
    VStack(spacing: 10) {
      Text("See your Kickbacks earnings").font(.headline)
      Text("Read-only · your own account only").font(.caption).foregroundStyle(.secondary)
      Button(action: vm.signIn) {
        Text("Sign in with Google").frame(maxWidth: .infinity)
      }.buttonStyle(.borderedProminent).tint(.green)
      footer(showData: false)
    }.frame(maxWidth: .infinity)
  }

  private var signingIn: some View {
    VStack(spacing: 10) {
      ProgressView()
      Text("Opening your browser…").font(.headline)
      Text("Finish signing in with Google, then come back.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("Cancel", action: vm.cancelLogin)
    }.frame(maxWidth: .infinity).padding(.vertical, 6)
  }

  private var signedIn: some View {
    VStack(alignment: .leading, spacing: 6) {
      bannerView
      row("Today", m.today, big: true)
      if m.collecting {
        Text("Collecting your trend… charts appear within the hour")
          .font(.caption).foregroundStyle(.secondary)
          .padding(8).frame(maxWidth: .infinity)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
      } else if !m.spark.isEmpty {
        HStack { Text(m.spark).foregroundStyle(.green); Spacer(); Text("last 24h").font(.caption).foregroundStyle(.secondary) }
      }
      row("Lifetime", m.lifetime)
      if !m.rate.isEmpty { row("Rate", "\(m.rate) \(arrow)") }
      if !m.cap.isEmpty { row("Daily cap", "\(m.cap) · \(m.capPct)%") }
      if let ago = m.lastEarnedAgoSeconds, m.state == .stalled || m.state == .killed {
        row("Last earned", agoText(ago))
      }
      if !m.ad.isEmpty {
        Divider()
        Text("Now showing").font(.caption).foregroundStyle(.secondary)
        Button(action: openAd) { Text(m.ad).lineLimit(1) }.buttonStyle(.link)
        if let t = m.viewThresholdSeconds {
          Text("Earn after \(t)s of viewing" + (m.ads.count > 1 ? " · \(m.ads.count) ads in rotation" : ""))
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
      if m.ageSeconds > 180 {
        Text("⚠ Couldn’t refresh · showing data from \(agoText(m.ageSeconds))")
          .font(.caption).foregroundStyle(.secondary)
      }
      footer(showData: true)
    }
  }

  // MARK: pieces

  @ViewBuilder private var bannerView: some View {
    switch m.state {
    case .stalled: banner("⚠ Earnings flat while you’re active — VS Code may have stopped serving.", .orange)
    case .cap:     banner("✓ Daily cap reached — \(m.today). Resets in \(m.resets).", .green)
    case .killed:  banner("✕ Not earning — stopped or signed out in VS Code.", .red)
    case .noServe: banner("No ad serving right now — you’ll earn again when one shows.", .gray)
    default:       EmptyView()
    }
  }

  private func banner(_ text: String, _ color: Color) -> some View {
    Text(text).font(.caption).foregroundStyle(color)
      .padding(8).frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func footer(showData: Bool) -> some View {
    HStack {
      if showData {
        Button("📊 History") { openWindow(id: "history") }.buttonStyle(.link)
        Spacer()
        Button("↻ Refresh") { vm.refresh() }.buttonStyle(.link)
      } else {
        Spacer()
      }
      Menu("⋯") {
        if showData { Button("Sign out", action: vm.signOut) }
        Toggle("Start at login", isOn: Binding(get: LoginItem.isEnabled, set: LoginItem.setEnabled))
        Button("Quit") { NSApplication.shared.terminate(nil) }
      }.menuStyle(.borderlessButton).fixedSize()
    }
  }

  private func row(_ key: String, _ value: String, big: Bool = false) -> some View {
    HStack {
      Text(key).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(big ? .title2.bold() : .body)
    }
  }

  private var arrow: String { m.trend == "up" ? "▴" : m.trend == "down" ? "▾" : "—" }
  private var dotColor: Color {
    switch MenuPresentation.tint(state: m.state, phase: vm.phase) {
    case .amber: return .orange; case .green: return .green; case .red: return .red
    case .primary: return .green; case .muted: return .secondary
    }
  }
  private func agoText(_ sec: Int) -> String {
    sec >= 3600 ? "\(sec/3600)h ago" : sec >= 60 ? "\(sec/60)m ago" : "\(sec)s ago"
  }
  private func openAd() { if let u = URL(string: m.adUrl), !m.adUrl.isEmpty { NSWorkspace.shared.open(u) } }
}
```

- [ ] **Step 2: Add the `LoginItem` helper (native login-item toggle via ServiceManagement)**

Create `app/Sources/KickbacksBar/LoginItem.swift`:

```swift
import ServiceManagement

/// "Start at login" via the OS (no launchd plist needed for the GUI app).
enum LoginItem {
  static func isEnabled() -> Bool { SMAppService.mainApp.status == .enabled }
  static func setEnabled(_ on: Bool) {
    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
    catch { NSLog("LoginItem toggle failed: \(error)") }
  }
}
```

- [ ] **Step 3: Update the menu-bar label to use MenuPresentation**

In `app/Sources/KickbacksBar/KickbacksBarApp.swift`, replace the `label:` closure:

```swift
    } label: {
      Text(MenuPresentation.menuBarLabel(phase: vm.phase, menuValue: vm.model.menuValue))
        .foregroundStyle(labelColor(vm))
    }
```

And add this free function at file scope (below the struct):

```swift
private func labelColor(_ vm: MenuVM) -> Color {
  switch MenuPresentation.tint(state: vm.model.state, phase: vm.phase) {
  case .amber: return .orange
  case .green: return .green
  case .red: return .red
  case .primary, .muted: return .primary
  }
}
```

(Add `import KickbacksKit` to `KickbacksBarApp.swift` if not already present.)

- [ ] **Step 4: Build the whole app**

Run: `cd app && swift build`
Expected: `Build complete!` (resolves the Task-10 cross-reference too).

- [ ] **Step 5: Commit**

```bash
cd app && git add Sources/KickbacksBar/MenuContent.swift Sources/KickbacksBar/KickbacksBarApp.swift Sources/KickbacksBar/LoginItem.swift
git commit -m "feat(app): all panel states + K\$ menu-bar label + login-item toggle"
```

---

## Phase 4 — History window

### Task 12: HistoryVM

**Files:**
- Create: `app/Sources/KickbacksBar/HistoryVM.swift`

- [ ] **Step 1: Implement**

```swift
// app/Sources/KickbacksBar/HistoryVM.swift
import SwiftUI
import KickbacksKit

@MainActor final class HistoryVM: ObservableObject {
  @Published private(set) var model: HistoryModel?
  @Published private(set) var loading = true

  func load() {
    loading = true
    Task.detached(priority: .utility) {
      let h = ModelClient.history()
      await MainActor.run { self.model = h; self.loading = false }
    }
  }
}
```

- [ ] **Step 2: Build**

Run: `cd app && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd app && git add Sources/KickbacksBar/HistoryVM.swift
git commit -m "feat(app): HistoryVM"
```

### Task 13: History window view + Window scene

**Files:**
- Create: `app/Sources/KickbacksBar/HistoryWindow.swift`
- Modify: `app/Sources/KickbacksBar/KickbacksBarApp.swift` (add the `Window` scene)

- [ ] **Step 1: Implement the view (full / not-enough / empty)**

```swift
// app/Sources/KickbacksBar/HistoryWindow.swift
import SwiftUI
import KickbacksKit

struct HistoryWindow: View {
  @StateObject private var vm = HistoryVM()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let h = vm.model {
        header(h)
        if h.isEmpty { emptyState } else { chart(h); tiles(h); stats(h) }
      } else if vm.loading {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("Couldn’t load history.").foregroundStyle(.secondary)
      }
    }
    .padding(18)
    .frame(width: 460, height: 360)
    .onAppear { vm.load() }
  }

  private func header(_ h: HistoryModel) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 22) {
      stat("LIFETIME", usd(h.lifetimeUsd))
      stat("SINCE INSTALL", usd(h.sinceInstallUsd))
      Spacer()
      Text("\(h.daysTracked) day\(h.daysTracked == 1 ? "" : "s")").foregroundStyle(.secondary).font(.caption)
      Button("↻") { vm.load() }.buttonStyle(.borderless)
    }
  }

  private func chart(_ h: HistoryModel) -> some View {
    let maxUsd = max(h.daily.map(\.usd).max() ?? 1, 0.01)
    return VStack(alignment: .leading, spacing: 4) {
      GeometryReader { geo in
        HStack(alignment: .bottom, spacing: 4) {
          ForEach(Array(h.daily.enumerated()), id: \.offset) { _, d in
            RoundedRectangle(cornerRadius: 2)
              .fill(d.hitCap ? Color.orange : Color.green)
              .frame(height: max(3, geo.size.height * d.usd / maxUsd))
          }
        }
      }.frame(height: 110)
      Text("$ / day · amber = hit cap").font(.caption2).foregroundStyle(.secondary)
    }
  }

  private func tiles(_ h: HistoryModel) -> some View {
    HStack(spacing: 8) {
      tile("This week", usd(h.thisWeekUsd), dim: !h.hasEnough)
      tile("This month", usd(h.thisMonthUsd), dim: !h.hasEnough)
      tile("Best day", h.bestDay.map { usd($0.usd) } ?? "—", dim: h.bestDay == nil)
      tile("Avg/day", usd(h.avgPerDayUsd), dim: !h.hasEnough)
    }
  }

  @ViewBuilder private func stats(_ h: HistoryModel) -> some View {
    if !h.hasEnough {
      Text("Only \(h.daysTracked) day\(h.daysTracked == 1 ? "" : "s") tracked — weekly/monthly views fill in as you keep earning.")
        .font(.caption).foregroundStyle(.orange)
    } else {
      Text("● Hit cap \(h.capHitsLast7) of last 7 days   ● \(h.campaignsSeen) campaigns seen   ● \(fmt(h.activeHours))h active")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Text("📈 No history yet").font(.headline)
      Text("Your first full day appears tomorrow. Kickbacks charts your earnings as you use it.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Text("Tip: keep the background poller on so days aren’t missed.").font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 130)
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
  }

  // helpers
  private func stat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.title3.bold())
    }
  }
  private func tile(_ label: String, _ value: String, dim: Bool) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.headline).foregroundStyle(dim ? .secondary : .primary)
    }
    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
  }
  private func usd(_ n: Double) -> String { "$" + String(format: "%.2f", n) }
  private func fmt(_ n: Double) -> String { String(format: "%.1f", n) }
}
```

- [ ] **Step 2: Add the Window scene**

In `app/Sources/KickbacksBar/KickbacksBarApp.swift`, inside `var body: some Scene`, add after the `MenuBarExtra { … }` block:

```swift
    Window("Kickbacks — History", id: "history") {
      HistoryWindow()
    }
    .windowResizability(.contentSize)
```

- [ ] **Step 3: Build**

Run: `cd app && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run the Swift test suite (no regressions)**

Run: `cd app && swift test`
Expected: PASS (ModelTests, HistoryModelTests, MenuPresentationTests).

- [ ] **Step 5: Commit**

```bash
cd app && git add Sources/KickbacksBar/HistoryWindow.swift Sources/KickbacksBar/KickbacksBarApp.swift
git commit -m "feat(app): History window (chart/tiles/empty) + Window scene"
```

---

## Phase 5 — Integration, build & QA

### Task 14: Build, install, and manual QA

**Files:** none (verification only)

- [ ] **Step 1: Full CLI gate**

Run: `cd cli && bunx --bun tsc --noEmit && bun test`
Expected: tsc clean; all tests pass (history + model additions included).

- [ ] **Step 2: Full Swift gate**

Run: `cd app && swift build && swift test`
Expected: `Build complete!` and all tests pass.

- [ ] **Step 3: Build + install the app**

Run: `bash scripts/install-app.sh`
Expected: `OK: installed /Applications/Kickbacks.app` with `-> bundled app/Resources/AppIcon.icns`.

- [ ] **Step 4: Verify `kickbacks history` from the bundled CLI**

Run: `/Applications/Kickbacks.app/Contents/MacOS/kickbacks history`
Expected: one line of JSON (day-one/empty shape is fine on a fresh history).

- [ ] **Step 5: Manual QA checklist (needs the GUI; record results in the PR/commit message)**

- [ ] Launch: `open -a Kickbacks` → menu bar shows `K$ —` (signed out).
- [ ] Click → **Sign in with Google** → panel shows spinner; browser opens; after Google consent the panel flips to data and the menu bar shows `K$ <value>`. (This verifies the open item from the spec: `kickbacks login` completes when spawned headlessly. If the browser never opens or it hangs, fall back to opening Terminal for login — see spec — and note it.)
- [ ] First run shows the "Collecting your trend…" placeholder (until ≥2 samples), then the sparkline.
- [ ] `📊 History` opens the window; with little data it shows "not enough" / empty messaging; tiles dim appropriately.
- [ ] Overflow `⋯` → Sign out returns to the signed-out panel; "Start at login" toggles (check System Settings → General → Login Items).
- [ ] Leave it running; confirm the menu-bar value updates and tints (amber/red) when state changes.

- [ ] **Step 6: Commit any QA-driven fixes, then a final marker commit**

```bash
git add -A && git commit -m "chore(app): menu-bar redesign QA pass"
```

---

## Notes / known follow-ups

- **Headless login:** the plan assumes `kickbacks login` opens the browser + runs its callback server when spawned without a TTY (its `openBrowser` uses `open` and it polls in-process). Verified in Task 14 Step 5. If a TTY is required, add a `login --json`/non-interactive mode to the CLI and have `startLogin` use it — the app already detects success via `model`’s `signedIn`, so no Swift change is needed.
- **Tiles labels:** "This week/This month" are rolling 7/30-day sums (see `summarize`). Rename in `HistoryWindow` if calendar-period semantics are preferred later.
- **activeHours/campaignsSeen** are richest when the background poller is running (it records `active` and distinct ads); plain app refreshes still contribute samples.
