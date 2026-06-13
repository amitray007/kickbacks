# Kickback — Plan 3: launchd poller + stall watchdog

> **For agentic workers:** implement task-by-task with TDD. Steps use `- [ ]`. Live in `cli/`. Commit per task on `main`.

**Goal:** A background poller (`kickback poll`, one cycle) that launchd runs every few minutes — it samples portfolio+earnings into local history (even with VS Code closed), and fires macOS notifications for the two events that matter: **stall** ("you're coding but `today_usd` is flat — the ad injection may have broken") and **cap hit**. Plus `kickback poller install|uninstall|status` to manage the launchd agent. This turns the amnesiac backend into trend/rate history (design §3–§5) and delivers the watchdog USP (§4 P1, §7).

## Decisions (made autonomously 2026-06-13 — review & redirect welcome)

- **D1 · Execution model:** launchd **`StartInterval`** runs `kickback poll` (one cycle, then exits) every `KICKBACK_POLL_SECONDS` (default 180). No long-running daemon — crash-resilient, no leak; state persists in SQLite. (launchd restarts it each interval; that *is* the "watchdog keep-alive".)
- **D2 · Activity signal (for stall):** a file is "active" if any file under the configured transcript dirs was modified within the window. Default dir: `~/.claude/projects` (override `KICKBACK_ACTIVITY_DIRS`, colon-separated). **Heuristic — confirm the real CC/Codex transcript locations on your machine.** Fail-safe: if it never reads "active", stall simply never fires (no false alarms).
- **D3 · Notifications:** macOS `osascript -e 'display notification …'` (built-in, no dep). No-op on non-darwin. Injected for tests.
- **D4 · De-dup:** a `kv` table in the store records last-fired markers. Stall fires **once per stall episode** (re-arms when earning resumes); cap fires **once per cap period** (re-arms when `reset_seconds` rolls over / scope changes).
- **D5 · Schema migration:** store `user_version` 1 → 2; `ALTER TABLE samples` adds `cap_scope TEXT, cap_usd REAL, cap_reset_s INTEGER, active INTEGER` (design §5 sketch). Old rows get NULL. `Sample` gains optional fields; Plan 1/2 callers omit them (stored NULL) and keep working.

**Read-only invariant preserved:** the poller only GETs `/v1/portfolio` + `/v1/earnings` (+ auth-lifecycle). Never `/v1/metrics`.

---

## File Structure

```
cli/src/
  config.ts     # + POLL_SECONDS, ACTIVITY_DIRS, ACTIVITY_WINDOW_MS, STALL_WINDOW_MS, LAUNCHD_LABEL
  types.ts      # Sample += active?/capScope?/capUsd?/capResetS? (all optional)
  store.ts      # migrate v1→v2; insertSample writes new cols; + getState/setState (kv table)
  activity.ts   # NEW — isActive(dirs, now, windowMs) via newest mtime under dirs (DI fs)
  alerts.ts     # NEW — pure decideAlerts(...) → {stall?, cap?} with de-dup vs prior kv state
  notify.ts     # NEW — notify(title, body) via osascript; darwin-only; DI-friendly
  poll.ts       # NEW — runPoll(deps): one cycle (fetch → active → record → decide → notify → persist state)
  launchd.ts    # NEW — plistContent(label, binPath, seconds) pure; install/uninstall/status (launchctl)
  cli.ts        # + `poll` and `poller install|uninstall|status`
cli/test/
  store.test.ts     # + v2 migration + kv round-trip
  activity.test.ts  # NEW
  alerts.test.ts    # NEW
  poll.test.ts      # NEW (DI everything; in-memory store; fake fetch/notify/active/now)
  launchd.test.ts   # NEW (plistContent pure)
```

`activity`/`alerts`/`poll` are pure/DI and fully unit-tested. `notify` (osascript) and `launchd` install/uninstall are side-effecting — `plistContent` is tested; the actual `launchctl load` + real notifications are **user QA** (can't run on their system from here).

---

## Task 1 — Schema v2 migration + `kv` state (store.ts)

**Files:** `cli/src/types.ts`, `cli/src/store.ts`, `cli/test/store.test.ts`.

- [ ] **Step 1:** extend `Sample` in `types.ts` (append optional fields; Plan 1/2 callers unaffected):
```ts
export interface Sample {
  ts: number;
  lifetimeUsd: number;
  todayUsd: number;
  adId: string;
  kill: boolean;
  active?: boolean | null;     // was the editor active at sample time (Plan 3 poller)
  capScope?: string | null;    // "hourly" | "daily"
  capUsd?: number | null;
  capResetS?: number | null;
}
```

- [ ] **Step 2: failing tests** (`store.test.ts`) — migration + kv + full-sample round-trip:
```ts
test("openStore migrates v1 → v2 (adds cap_*/active, version 2)", () => {
  const store = openStore(":memory:");
  expect(store.userVersion()).toBe(2);
  store.insertSample({ ts: 1, lifetimeUsd: 1, todayUsd: 0.5, adId: "a", kill: false,
    active: true, capScope: "daily", capUsd: 1, capResetS: 3600 });
  const r = store.latest()!;
  expect(r.active).toBe(true);
  expect(r.capScope).toBe("daily");
  expect(r.capResetS).toBe(3600);
});

test("kv state round-trips", () => {
  const store = openStore(":memory:");
  expect(store.getState("k")).toBeNull();
  store.setState("k", "v");
  expect(store.getState("k")).toBe("v");
});
```

- [ ] **Step 3:** in `store.ts`: bump the migration, add columns idempotently, add the kv table + methods. Replace the version block with:
```ts
const readVersion = (): number =>
  Number((db.query("PRAGMA user_version").get() as any)?.user_version ?? 0);
const hasColumn = (table: string, col: string): boolean =>
  (db.query(`PRAGMA table_info(${table})`).all() as any[]).some((c) => c.name === col);
if (readVersion() < 2) {
  for (const [col, type] of [["cap_scope", "TEXT"], ["cap_usd", "REAL"], ["cap_reset_s", "INTEGER"], ["active", "INTEGER"]] as const) {
    if (!hasColumn("samples", col)) db.run(`ALTER TABLE samples ADD COLUMN ${col} ${type}`);
  }
  db.run("PRAGMA user_version = 2");
}
db.run("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT)");
```
Update `rowToSample` to read the new cols (`active: r.active == null ? null : !!r.active`, `capScope: r.cap_scope ?? null`, etc.). Update `insertSample` to the 9-col insert (`INSERT OR REPLACE INTO samples (ts,lifetime_usd,today_usd,ad_id,kill,active,cap_scope,cap_usd,cap_reset_s) VALUES (?,?,?,?,?,?,?,?,?)`, mapping `undefined`→`null`). Add to `Store`:
```ts
getState(key: string): string | null;
setState(key: string, value: string): void;
userVersion(): number;
```
impl:
```ts
getState(key) { const r = db.query("SELECT value FROM kv WHERE key=?").get(key) as any; return r ? r.value : null; },
setState(key, value) { db.run("INSERT OR REPLACE INTO kv VALUES (?,?)", [key, value]); },
```
> Use a named-column INSERT so the existing 5-col Plan 1/2 callers keep compiling — switch `insertSample` to named columns and pass the new fields as `s.active ?? null` etc.

- [ ] **Step 4:** `bun test test/store.test.ts` → PASS. `bun test` (full) → all green (Plan 1/2 inserts still work). `tsc` clean.
- [ ] **Step 5:** commit `feat(store): schema v2 (cap_*/active columns) + kv state`.

---

## Task 2 — Activity detection (activity.ts)

**Files:** `cli/src/activity.ts`, `cli/test/activity.test.ts`.

- [ ] **Step 1: failing test** — newest mtime under any dir within the window:
```ts
import { isActive } from "../src/activity";
import { mkdtempSync, writeFileSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os"; import { join } from "node:path";

test("isActive true iff a file under dirs was modified within the window", () => {
  const dir = mkdtempSync(join(tmpdir(), "kb-act-"));
  const f = join(dir, "session.jsonl"); writeFileSync(f, "x");
  const now = 2_000_000;
  utimesSync(f, new Date(now - 60_000), new Date(now - 60_000)); // 1 min ago
  expect(isActive([dir], now, 300_000)).toBe(true);              // within 5 min
  utimesSync(f, new Date(now - 600_000), new Date(now - 600_000)); // 10 min ago
  expect(isActive([dir], now, 300_000)).toBe(false);
  expect(isActive(["/no/such/dir"], now, 300_000)).toBe(false);  // missing dir → false
});
```

- [ ] **Step 2:** `activity.ts` — recursive newest-mtime scan, robust to missing dirs:
```ts
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

/** Newest mtime (unix ms) under `dir`, recursing shallowly; 0 if unreadable/empty. */
function newestMtime(dir: string, depth = 3): number {
  let newest = 0;
  let entries: import("node:fs").Dirent[] = [];
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return 0; }
  for (const e of entries) {
    const p = join(dir, e.name);
    try {
      if (e.isDirectory()) { if (depth > 0) newest = Math.max(newest, newestMtime(p, depth - 1)); }
      else newest = Math.max(newest, statSync(p).mtimeMs);
    } catch { /* skip */ }
  }
  return newest;
}

/** True if any file under any dir was modified within `windowMs` of `now`. Heuristic
 *  for "the user is actively coding"; fail-safe (false when unsure → no stall alarm). */
export function isActive(dirs: string[], now: number, windowMs: number): boolean {
  return dirs.some((d) => { const m = newestMtime(d); return m > 0 && m >= now - windowMs && m <= now + 60_000; });
}
```

- [ ] **Step 3:** `bun test test/activity.test.ts` → PASS.
- [ ] **Step 4:** commit `feat(activity): editor-activity detection via transcript mtime`.

---

## Task 3 — Alert decisions + de-dup (alerts.ts)

**Files:** `cli/src/alerts.ts`, `cli/test/alerts.test.ts`. Reuses `isStalled` (derive.ts).

- [ ] **Step 1: failing tests** — pure decision over samples + prior kv markers:
```ts
import { decideAlerts } from "../src/alerts";
import type { Sample, Earnings } from "../src/types";
const s = (ts: number, todayUsd: number, active: boolean): Sample =>
  ({ ts, todayUsd, lifetimeUsd: todayUsd, adId: "a", kill: false, active });

test("stall fires once: active + flat across window, then re-arms when earning resumes", () => {
  const now = 1_000_000;
  const flat = [s(now - 240_000, 0.4, true), s(now - 60_000, 0.4, true)];
  const cap: Earnings = { cap: null };
  const a1 = decideAlerts({ samples: flat, earnings: cap, now, stallWindowMs: 300_000, state: {} });
  expect(a1.stall).toBe(true);
  // already-fired marker suppresses a repeat
  const a2 = decideAlerts({ samples: flat, earnings: cap, now, stallWindowMs: 300_000, state: { stallActive: "1" } });
  expect(a2.stall).toBe(false);
});

test("cap fires once per period (keyed by scope+reset bucket)", () => {
  const now = 1_000_000;
  const samples = [s(now - 60_000, 1.0, true)];
  const e: Earnings = { cap: { scope: "daily", capUsd: 1.0, resetSeconds: 3600 } };
  const a1 = decideAlerts({ samples, earnings: e, now, stallWindowMs: 300_000, state: {} });
  expect(a1.cap?.scope).toBe("daily");
  const a2 = decideAlerts({ samples, earnings: e, now, stallWindowMs: 300_000, state: { capFired: a1.cap!.key } });
  expect(a2.cap).toBeUndefined();
});
```

- [ ] **Step 2:** `alerts.ts`:
```ts
import type { Sample, Earnings } from "./types";
import { isStalled } from "./derive";

export interface AlertInput {
  samples: Sample[]; earnings: Earnings | null; now: number; stallWindowMs: number;
  state: { stallActive?: string; capFired?: string };
}
export interface Alerts {
  stall?: boolean;
  cap?: { scope: string; key: string };
  /** kv updates to persist after firing (caller writes these). */
  state: { stallActive: string; capFired: string | null };
}

export function decideAlerts(i: AlertInput): Alerts {
  const recent = [...i.samples].sort((a, b) => a.ts - b.ts);
  const latest = recent[recent.length - 1];
  const active = latest?.active === true;
  const stalledNow = isStalled({ samples: recent, now: i.now, windowMs: i.stallWindowMs, active });
  const wasStalled = i.state.stallActive === "1";
  const out: Alerts = { state: { stallActive: stalledNow ? "1" : "", capFired: i.state.capFired ?? null } };
  if (stalledNow && !wasStalled) out.stall = true; // edge-triggered: fire once per episode

  const cap = i.earnings?.cap;
  const today = latest?.todayUsd ?? 0;
  if (cap && today >= cap.capUsd) {
    const key = `${cap.scope}:${Math.floor(i.now / Math.max(1, cap.resetSeconds * 1000))}`; // period bucket
    if (i.state.capFired !== key) { out.cap = { scope: cap.scope, key }; out.state.capFired = key; }
  }
  return out;
}
```

- [ ] **Step 3:** `bun test test/alerts.test.ts` → PASS.
- [ ] **Step 4:** commit `feat(alerts): edge-triggered stall + cap alerts with de-dup`.

---

## Task 4 — Notifier (notify.ts)

**Files:** `cli/src/notify.ts`. (Thin; covered indirectly by poll's DI test.)

- [ ] **Step 1:** `notify.ts` — macOS osascript, darwin-only, never throws:
```ts
import { spawn } from "node:child_process";

/** Fire a macOS notification (osascript). No-op off darwin; best-effort (never throws). */
export function notify(title: string, body: string): void {
  if (process.platform !== "darwin") return;
  const script = `display notification ${JSON.stringify(body)} with title ${JSON.stringify(title)}`;
  try { spawn("osascript", ["-e", script], { stdio: "ignore", detached: true }).unref(); } catch { /* ignore */ }
}
export type Notifier = (title: string, body: string) => void;
```

- [ ] **Step 2:** `tsc` clean. commit `feat(notify): macOS osascript notifier`.

---

## Task 5 — Poll cycle + `kickback poll` (poll.ts, cli.ts)

**Files:** `cli/src/poll.ts`, `cli/src/cli.ts`, `cli/test/poll.test.ts`.

- [ ] **Step 1: failing test** — one cycle records a full sample and fires the stall notification, all injected:
```ts
import { runPoll } from "../src/poll";
import { openStore } from "../src/store";
import type { Portfolio, Earnings } from "../src/types";

const P: Portfolio = { lifetimeUsd: 1, todayUsd: 0.4, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "a", campaignId: "c", text: "x", clickUrl: "", bannerEnabled: false }] };
const E: Earnings = { cap: null };

test("runPoll records an active sample; fires stall when active + flat", async () => {
  const store = openStore(":memory:");
  const now0 = 1_000_000; const fired: string[] = [];
  const deps = {
    fetchPortfolio: async () => P, fetchEarnings: async () => E, store,
    isActive: () => true, notify: (t: string) => { fired.push(t); },
    stallWindowMs: 300_000,
  };
  await runPoll({ ...deps, now: now0 - 240_000 });             // first flat sample
  await runPoll({ ...deps, now: now0 });                       // second flat sample → stall
  expect(store.latest()!.active).toBe(true);
  expect(fired.some((t) => /Kickback/.test(t))).toBe(true);
});
```

- [ ] **Step 2:** `poll.ts`:
```ts
import type { Portfolio, Earnings } from "./types";
import type { Store } from "./store";
import { earningState } from "./derive";
import { decideAlerts } from "./alerts";
import type { Notifier } from "./notify";

export interface PollDeps {
  fetchPortfolio: () => Promise<Portfolio>;
  fetchEarnings: () => Promise<Earnings>;
  store: Store;
  isActive: () => boolean;
  notify: Notifier;
  now: number;
  stallWindowMs: number;
}

/** One poll cycle: fetch, detect activity, record a full sample, decide + fire alerts,
 *  persist de-dup state. Pure of auth/launchd — the caller injects authed fetchers. */
export async function runPoll(d: PollDeps): Promise<void> {
  const p = await d.fetchPortfolio();
  const e = await d.fetchEarnings().catch(() => null);
  const active = d.isActive();
  d.store.insertSample({
    ts: d.now, lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd, adId: p.ads[0]?.adId ?? "", kill: p.kill,
    active, capScope: e?.cap?.scope ?? null, capUsd: e?.cap?.capUsd ?? null, capResetS: e?.cap?.resetSeconds ?? null,
  });
  const samples = d.store.recentSince(d.now - 24 * 3_600_000);
  const a = decideAlerts({ samples, earnings: e, now: d.now, stallWindowMs: d.stallWindowMs,
    state: { stallActive: d.store.getState("stallActive") ?? "", capFired: d.store.getState("capFired") ?? undefined } });
  if (a.stall) d.notify("Kickback — not earning", "You're coding but today's earnings are flat. The ad injection may have broken — run “Kickbacks: Restore”.");
  if (a.cap) d.notify("Kickback — cap reached", `Your ${a.cap.scope} cap is hit; no more earning until it resets.`);
  d.store.setState("stallActive", a.state.stallActive);
  if (a.state.capFired !== null) d.store.setState("capFired", a.state.capFired);
  if (earningState(p, e) === "earning") d.store.setState("capFired", ""); // re-arm cap when earning again
}
```

- [ ] **Step 3:** wire `cli.ts` — add `poll: cmdPoll` (one cycle for launchd) using the real authed fetchers + activity + notify:
```ts
import { runPoll } from "./poll";
import { isActive } from "./activity";
import { notify } from "./notify";
import { ACTIVITY_DIRS, ACTIVITY_WINDOW_MS, STALL_WINDOW_MS } from "./config";

async function cmdPoll() {
  if (!loadTokens()) { console.error("Not signed in. Run: kickback login"); process.exit(1); }
  const store = openStore(DB_FILE);
  try {
    await runPoll({
      fetchPortfolio: () => runAuthed((tk) => fetchPortfolio(deps(tk))),
      fetchEarnings: () => runAuthed((tk) => fetchEarnings(deps(tk))),
      store, isActive: () => isActive(ACTIVITY_DIRS, Date.now(), ACTIVITY_WINDOW_MS),
      notify, now: Date.now(), stallWindowMs: STALL_WINDOW_MS,
    });
  } finally { store.close(); }
}
```
Add `config.ts`: `ACTIVITY_DIRS` (from `KICKBACK_ACTIVITY_DIRS` or `[~/.claude/projects]`), `ACTIVITY_WINDOW_MS` (default 300_000), `STALL_WINDOW_MS` (default 600_000), `POLL_SECONDS`, `LAUNCHD_LABEL = "ai.kickback.poller"`. Register `poll` in the table + usage. (`poll` is for launchd; harmless if run by hand.)

- [ ] **Step 4:** `bun test test/poll.test.ts` + full suite + `tsc` → green.
- [ ] **Step 5:** commit `feat(poll): one-cycle poller (sample + stall/cap alerts)`.

---

## Task 6 — launchd agent + `poller install|uninstall|status` (launchd.ts, cli.ts)

**Files:** `cli/src/launchd.ts`, `cli/src/cli.ts`, `cli/test/launchd.test.ts`.

- [ ] **Step 1: failing test** — `plistContent` is a pure, correct plist:
```ts
import { plistContent } from "../src/launchd";
test("plistContent embeds label, program args, interval", () => {
  const xml = plistContent("ai.kickback.poller", "/usr/local/bin/kickback", 180);
  expect(xml).toContain("<string>ai.kickback.poller</string>");
  expect(xml).toContain("<string>/usr/local/bin/kickback</string>");
  expect(xml).toContain("<string>poll</string>");
  expect(xml).toContain("<integer>180</integer>");
});
```

- [ ] **Step 2:** `launchd.ts` — pure `plistContent` + side-effecting install/uninstall/status:
```ts
import { writeFileSync, rmSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

export function plistContent(label: string, binPath: string, seconds: number): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array><string>${binPath}</string><string>poll</string></array>
  <key>StartInterval</key><integer>${seconds}</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>${join(homedir(), "Library/Logs", label + ".log")}</string>
</dict></plist>
`;
}
const plistPath = (label: string) => join(homedir(), "Library/LaunchAgents", `${label}.plist`);

export function installAgent(label: string, binPath: string, seconds: number): string {
  const path = plistPath(label);
  mkdirSync(join(homedir(), "Library/LaunchAgents"), { recursive: true });
  writeFileSync(path, plistContent(label, binPath, seconds));
  spawnSync("launchctl", ["unload", path], { stdio: "ignore" });
  spawnSync("launchctl", ["load", path], { stdio: "ignore" });
  return path;
}
export function uninstallAgent(label: string): void {
  const path = plistPath(label);
  spawnSync("launchctl", ["unload", path], { stdio: "ignore" });
  try { rmSync(path); } catch { /* ignore */ }
}
export function agentInstalled(label: string): boolean { return existsSync(plistPath(label)); }
```

- [ ] **Step 3:** `cli.ts` — `poller` subcommand. Resolve `binPath` = `process.execPath` if compiled, else instruct to `bun build`. For the common (compiled brew) case `process.execPath` is the `kickback` binary:
```ts
async function cmdPoller() {
  const sub = (process.argv[3] || "status").toLowerCase();
  if (sub === "install") {
    const path = installAgent(LAUNCHD_LABEL, process.execPath, POLL_SECONDS);
    console.log(`installed launchd agent → ${path}\npolling every ${POLL_SECONDS}s. Uninstall: kickback poller uninstall`);
  } else if (sub === "uninstall") { uninstallAgent(LAUNCHD_LABEL); console.log("uninstalled."); }
  else { console.log(`poller ${agentInstalled(LAUNCHD_LABEL) ? "installed" : "not installed"} (${LAUNCHD_LABEL})`); }
}
```
Register `poller` in the table + usage.
- [ ] **Step 4:** `bun test test/launchd.test.ts` + full suite + `tsc` green. **Do NOT run `poller install` here** — it's a system change + starts background polling; that's the user's to run.
- [ ] **Step 5:** commit `feat(launchd): poller install/uninstall/status + plist`.

---

## Task 7 — Review, docs, manual QA handoff

- [ ] Full `bun test` + `tsc` green; `bun build --compile` smoke (binary still builds/runs).
- [ ] compound-engineering review (TS + simplicity) over `store`/`activity`/`alerts`/`poll`/`launchd` diff; triage + apply.
- [ ] README (root + cli): document `poll` / `poller install` + the `KICKBACK_*` poller envs. design.md: note Plan 3 shipped; §13.x activity-dir heuristic.
- [ ] **Manual QA (user, real macOS):** confirm CC/Codex transcript dir(s) for D2 (set `KICKBACK_ACTIVITY_DIRS` if needed); `kickback poller install`; verify a sample lands every interval (`kickback status`/`watch` shows rate building) and that a forced stall/cap produces a notification; `kickback poller uninstall` to stop.

---

## Self-Review

**Spec coverage (design §3–§5, §4 P1, §7):** periodic sampling ✅ (Task 5 + launchd Task 6), local history with cap/active ✅ (Task 1), stall watchdog ✅ (Tasks 2–3, the USP), cap alert ✅ (Task 3), editor-independent (launchd) ✅ (Task 6), read-only ✅ (only portfolio/earnings GETs). Sparkline/rate now become real once the agent samples regularly.
**Testable core:** migration, activity, alerts, poll cycle, plist — all unit-tested with DI; only real launchd-load + live notifications are user-QA.
**Type consistency:** `Sample` optional fields (Task 1) flow through `insertSample`/`recentSince` → `runPoll` (Task 5); `decideAlerts` Alerts shape (Task 3) consumed in Task 5; `Notifier` (Task 4) injected in Task 5.
**De-dup correctness:** stall is edge-triggered (`stallActive` "1"→re-arm on resume); cap keyed by `scope:period-bucket`, re-armed when `earningState==="earning"`. No alert storms.
