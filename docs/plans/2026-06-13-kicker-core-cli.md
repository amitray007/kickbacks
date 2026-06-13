# Kickback — Core + CLI MVP Implementation Plan

> **Naming note (2026-06-13):** authored as **"Kicker"** (`kicker` binary, `~/.config/kicker`, `KICKER_*`). The tool was later renamed **Kickback** (`kickback`, `~/.config/kickback`, `KICKBACK_*`) and the package dir `kicker/` → `cli/`. Read the historical `kicker`/`kicker/` references below accordingly.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working `kicker` CLI that signs into your own Kickbacks account, fetches your portfolio + earnings, records a local history sample, and prints it — read-only, zero billing calls.

**Architecture:** A single Bun + TypeScript package under `kicker/`. Pure, testable modules (`config`, `api`, `auth`, `store`, `derive`) with a thin `cli` dispatcher on top. Network and clock are dependency-injected so every module is unit-testable without hitting the real backend. SQLite (via built-in `bun:sqlite`) accumulates the history the server doesn't keep.

**Tech Stack:** Bun (runtime, test runner, `bun:sqlite`, `bun build --compile`), TypeScript, global `fetch`. No third-party runtime deps in this plan (OpenTUI arrives in Plan 2).

**Scope boundary:** This plan stops at a text-output CLI. OpenTUI rendering (Plan 2), the launchd poller + watchdog (Plan 3), the Swift menu app (Plan 4), and Homebrew packaging (Plan 5) are separate plans. The project lives in `kicker/` inside this repo for now; extraction to its own repo happens in Plan 5.

**API contract reference:** `docs/design.md` §6.

---

## Amendments — pre-build decisions (2026-06-13)

Four refinements agreed before implementation, validated against the proven prototype (`../tries/reverse-engineer-kickbacks-ai/kb.mjs`) and design §4/§5. Apply these on top of the task code below; everything else in the plan is unchanged.

**A1 — Restore `raw` command (design §4 P0).** Add `fetchRaw` to `api.ts` and a `raw` command to the CLI. `raw` dumps the *unparsed* server JSON (parsing would hide the API drift it exists to diagnose).

`api.ts` — add after `fetchEarnings`:
```ts
export async function fetchRaw(d: ApiDeps, path: string): Promise<unknown> {
  const r = await d.fetch(`${d.base}${path}`, { headers: { authorization: `Bearer ${d.token}` } });
  if (!r.ok) throw new Error(`raw HTTP ${r.status}`);
  return r.json();
}
```
`api.test.ts` — add (and import `fetchRaw`):
```ts
test("fetchRaw returns unparsed server JSON (drift debugging)", async () => {
  const fakeFetch = async () => new Response(JSON.stringify({ weird_new_field: 1 }), { status: 200 });
  const j: any = await fetchRaw({ fetch: fakeFetch as any, token: "TK", base: "https://b", ccVersion: "9" }, "/v1/portfolio");
  expect(j.weird_new_field).toBe(1);
});
```

**A2 — Defensive ad-field parsing (API-drift insurance; the prototype hedged both casings).** In `parsePortfolio`, accept snake_case OR camelCase per ad field:
```ts
const ads: Ad[] = Array.isArray(j?.ads) ? j.ads.map((a: any) => ({
  adId: String(a?.ad_id ?? a?.adId ?? ""),
  campaignId: String(a?.campaign_id ?? a?.campaignId ?? ""),
  text: String(a?.title_text ?? a?.adText ?? ""),
  clickUrl: typeof (a?.click_url ?? a?.clickUrl) === "string" ? (a.click_url ?? a.clickUrl) : "",
  bannerEnabled: (a?.banner_enabled ?? a?.bannerEnabled) === true,
})) : [];
```
`api.test.ts` — add:
```ts
test("parsePortfolio accepts camelCase ad fields", () => {
  const p = parsePortfolio({ ads: [{ adId: "a2", campaignId: "c2", adText: "Buy Y",
    clickUrl: "https://y.test", bannerEnabled: true }] });
  expect(p.ads[0]).toEqual({ adId: "a2", campaignId: "c2", text: "Buy Y",
    clickUrl: "https://y.test", bannerEnabled: true });
});
```

**A3 — `logout` revokes server-side (matches prototype).** Add `signout` to `auth.ts`; `cmdLogout` calls it best-effort before clearing the local file.

`auth.ts` — add after `refresh`:
```ts
export async function signout(d: AuthDeps, refreshToken: string): Promise<void> {
  await d.fetch(`${d.base}/v1/auth/signout`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
}
```
`auth.test.ts` — add (and import `signout`):
```ts
test("signout posts the refresh_token to /v1/auth/signout", async () => {
  let url = "", body = "";
  const fakeFetch = async (u: string, init: any) => { url = u; body = init.body;
    return new Response(null, { status: 200 }); };
  await signout({ fetch: fakeFetch as any, base }, "RT");
  expect(url).toBe("https://b/v1/auth/signout");
  expect(JSON.parse(body)).toEqual({ refresh_token: "RT" });
});
```
`cli.ts` — add `cmdRaw` + `cmdLogout` (and import `fetchRaw` from `./api`, `signout` from `./auth`):
```ts
async function cmdRaw() {
  const [portfolio, earnings] = await Promise.all([
    authed((tk) => fetchRaw(deps(tk), `/v1/portfolio?claude_code_version=${encodeURIComponent(CC_VERSION)}`)),
    authed((tk) => fetchRaw(deps(tk), "/v1/earnings")),
  ]);
  console.log(JSON.stringify({ portfolio, earnings }, null, 2));
}

async function cmdLogout() {
  const t = loadTokens();
  if (t?.refresh_token) await signout({ fetch, base: BASE }, t.refresh_token).catch(() => {});
  clearTokens();
  console.log("signed out.");
}
```
…and the dispatch table + usage line become:
```ts
const table: Record<string, () => unknown> = {
  login: cmdLogin, portfolio: cmdPortfolio, earnings: cmdEarnings,
  raw: cmdRaw, status: cmdStatus, logout: cmdLogout,
};
const fn = table[cmd];
if (!fn) { console.error("commands: login | portfolio | earnings | raw | status | logout"); process.exit(2); }
```

> The read-only line still holds: the only POSTs are auth lifecycle (`/v1/auth/refresh`, `/v1/auth/signout`). **Never** `/v1/metrics` or any billing/impression event.

**A4 — History schema: thin + version stamp.** Keep the plan's 5 columns; stamp `PRAGMA user_version = 1` so Plan 3's watchdog columns (`active`, cap) migrate cleanly. Expose the version for tests/migration.

`store.ts` — add `userVersion(): number` to the `Store` interface; after `CREATE TABLE`:
```ts
if (((db.query("PRAGMA user_version").get() as any)?.user_version ?? 0) < 1) {
  db.run("PRAGMA user_version = 1");
}
```
and in the returned object:
```ts
userVersion() { return (db.query("PRAGMA user_version").get() as any).user_version as number; },
```
`store.test.ts` — add:
```ts
test("openStore stamps schema version 1 (migration hook for Plan 3)", () => {
  expect(openStore(":memory:").userVersion()).toBe(1);
});
```

**Test counts after amendments:** api 6 · derive 6 · store 3 · auth 4 = **19 total** (Task 3 Step 4 → "6 tests", Task 5 Step 4 → "3 tests", Task 6 Step 4 → "4 tests", Task 7 Step 3 → "19 total").

**Execution ownership:** Tasks 0–7 implemented and tested through the automated layer (all unit tests + the no-auth `status` smoke test). **Task 7 Step 5 (real `kicker login` + confirming the VS Code extension still works) is the user's** — it needs an interactive Google login and is the empirical single-session test that resolves design §13.5.

---

## File Structure

> Renamed `kicker/` → `cli/` on 2026-06-13 (umbrella `kickbacks/` now holds `cli/` plus future `app/` + `packaging/`). The tree and the `cd kicker` commands below were authored pre-rename — read `kicker/` as `cli/`.

```
cli/
  package.json          # bun package, "bin": { "kicker": "./src/cli.ts" }, scripts
  tsconfig.json         # strict TS
  README.md             # quickstart
  src/
    config.ts           # base URL, cc version, file paths, env overrides
    types.ts            # shared types (Portfolio, Earnings, Tokens, Sample)
    api.ts              # parsePortfolio/parseEarnings (pure) + fetchPortfolio/fetchEarnings (DI fetch)
    auth.ts             # startLogin/pollOnce/refresh (DI fetch) + token file read/write
    store.ts            # bun:sqlite history store: open, insertSample, latest, recentSince
    derive.ts           # pure: ratePerHour, projectSecondsToCap, isStalled, fmtUsd, fmtDuration
    cli.ts              # arg dispatch + text rendering; wires the modules
  test/
    api.test.ts
    auth.test.ts
    store.test.ts
    derive.test.ts
```

Each module has one responsibility; `api`/`auth`/`store`/`derive` never import `cli`. `cli` is the only module allowed side effects at import-time-free (everything runs under `main()`).

---

## Task 0: De-risk spikes (verify before building)

**Files:** none (this is verification; record results in the PR/commit message).

- [ ] **Step 1: Ensure Bun is installed**

Run: `bun --version`
If missing: `brew install oven-sh/bun/bun` then re-run.
Expected: prints a version (≥ 1.1).

- [ ] **Step 2: Verify `bun:sqlite` works**

Run:
```bash
bun -e 'import{Database}from"bun:sqlite";const d=new Database(":memory:");d.run("create table t(x)");d.run("insert into t values(1)");console.log(d.query("select x from t").get())'
```
Expected: prints `{ x: 1 }`.

- [ ] **Step 3: Single-session auth probe (informs design §13.5)**

Goal: confirm whether a fresh CLI login would disturb the extension's session. Do NOT complete a second interactive login yet — just confirm the start endpoint behaves and note the risk.
Run:
```bash
bun -e 'const r=await fetch("https://kickbacks-backend-gmdaqm2c7q-uw.a.run.app/v1/auth/extension/start",{redirect:"manual"});console.log(r.status, new URL(r.headers.get("location")).host)'
```
Expected: `307 accounts.google.com`. Record in commit notes: "single-session behaviour to be confirmed on first real login; passive mode is the fallback (design §11)."

- [ ] **Step 4: Commit a note**

```bash
cd kicker 2>/dev/null || true
git add -A && git commit -m "chore: record build spikes (bun, bun:sqlite, auth start verified)" --allow-empty
```

---

## Task 1: Project scaffold

**Files:**
- Create: `kicker/package.json`
- Create: `kicker/tsconfig.json`
- Create: `kicker/.gitignore`

- [ ] **Step 1: Create `kicker/package.json`**

```json
{
  "name": "kicker",
  "version": "0.0.1",
  "type": "module",
  "private": true,
  "bin": { "kicker": "./src/cli.ts" },
  "scripts": {
    "test": "bun test",
    "start": "bun run ./src/cli.ts",
    "build": "bun build ./src/cli.ts --compile --outfile dist/kicker"
  },
  "engines": { "bun": ">=1.1.0" }
}
```

- [ ] **Step 2: Create `kicker/tsconfig.json`**

```json
{
  "compilerOptions": {
    "strict": true,
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "types": ["bun-types"],
    "noUncheckedIndexedAccess": true,
    "skipLibCheck": true
  }
}
```

- [ ] **Step 3: Create `kicker/.gitignore`**

```
node_modules/
dist/
*.db
```

- [ ] **Step 4: Install bun types and verify test runner**

Run: `cd kicker && bun add -d bun-types && bun test`
Expected: bun runs, reports "0 tests" (no test files yet) and exits 0.

- [ ] **Step 5: Commit**

```bash
cd kicker && git add -A && git commit -m "chore: scaffold kicker bun+ts package"
```

---

## Task 2: Types + config

**Files:**
- Create: `kicker/src/types.ts`
- Create: `kicker/src/config.ts`

- [ ] **Step 1: Create `kicker/src/types.ts`**

```ts
export interface Ad {
  adId: string;
  campaignId: string;
  text: string;
  clickUrl: string;
  bannerEnabled: boolean;
}
export interface Portfolio {
  lifetimeUsd: number;
  todayUsd: number;
  ads: Ad[];
  viewThresholdSeconds: number | null;
  kill: boolean;
}
export interface Cap {
  scope: "hourly" | "daily";
  capUsd: number;
  resetSeconds: number;
}
export interface Earnings {
  cap: Cap | null;
}
export interface Tokens {
  access_token: string;
  refresh_token?: string;
  client_id?: string;
}
export interface Sample {
  ts: number;          // unix ms
  lifetimeUsd: number;
  todayUsd: number;
  adId: string;
  kill: boolean;
}
```

- [ ] **Step 2: Create `kicker/src/config.ts`**

```ts
import { homedir } from "node:os";
import { join } from "node:path";

export const BASE =
  (process.env.KICKER_BASE || "https://kickbacks-backend-gmdaqm2c7q-uw.a.run.app")
    .replace(/\/+$/, "");
export const CC_VERSION = process.env.KICKER_CC_VERSION || "2.1.177";

export const CONFIG_DIR = join(homedir(), ".config", "kicker");
export const AUTH_FILE = join(CONFIG_DIR, "auth.json");
export const DB_FILE = join(CONFIG_DIR, "history.db");
```

- [ ] **Step 3: Commit**

```bash
cd kicker && git add -A && git commit -m "feat: add core types and config"
```

---

## Task 3: API client (pure parsers + DI fetch)

**Files:**
- Create: `kicker/src/api.ts`
- Test: `kicker/test/api.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// kicker/test/api.test.ts
import { test, expect } from "bun:test";
import { parsePortfolio, parseEarnings, fetchPortfolio } from "../src/api";

test("parsePortfolio normalizes server fields", () => {
  const p = parsePortfolio({
    kill: false,
    balances: { lifetime_usd: "1.50", today_usd: "0.25" },
    view_threshold_seconds: 15,
    ads: [{ ad_id: "a1", campaign_id: "c1", title_text: "Buy X",
            click_url: "https://x.test", banner_enabled: true }],
  });
  expect(p.lifetimeUsd).toBe(1.5);
  expect(p.todayUsd).toBe(0.25);
  expect(p.kill).toBe(false);
  expect(p.viewThresholdSeconds).toBe(15);
  expect(p.ads[0]).toEqual({ adId: "a1", campaignId: "c1", text: "Buy X",
    clickUrl: "https://x.test", bannerEnabled: true });
});

test("parsePortfolio tolerates missing fields", () => {
  const p = parsePortfolio({});
  expect(p.lifetimeUsd).toBe(0);
  expect(p.todayUsd).toBe(0);
  expect(p.ads).toEqual([]);
  expect(p.kill).toBe(false);
});

test("parseEarnings reads the cap", () => {
  const e = parseEarnings({ cap: { scope: "daily", cap_usd: "1.00", reset_seconds: 3600 } });
  expect(e.cap).toEqual({ scope: "daily", capUsd: 1, resetSeconds: 3600 });
});

test("fetchPortfolio sends bearer + cc version and parses", async () => {
  let seenUrl = ""; let seenAuth = "";
  const fakeFetch = async (url: string, init: any) => {
    seenUrl = url; seenAuth = init.headers.authorization;
    return new Response(JSON.stringify({ balances: { lifetime_usd: "2", today_usd: "1" } }),
      { status: 200 });
  };
  const p = await fetchPortfolio({ fetch: fakeFetch as any, token: "TK", base: "https://b", ccVersion: "9" });
  expect(seenUrl).toContain("/v1/portfolio?claude_code_version=9");
  expect(seenAuth).toBe("Bearer TK");
  expect(p.lifetimeUsd).toBe(2);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd kicker && bun test test/api.test.ts`
Expected: FAIL — `parsePortfolio` is not a function / module not found.

- [ ] **Step 3: Write `kicker/src/api.ts`**

```ts
import type { Portfolio, Earnings, Cap, Ad } from "./types";

const num = (v: unknown): number => {
  const n = typeof v === "string" ? parseFloat(v) : typeof v === "number" ? v : NaN;
  return Number.isFinite(n) ? n : 0;
};

export function parsePortfolio(j: any): Portfolio {
  const b = j?.balances ?? {};
  const ads: Ad[] = Array.isArray(j?.ads) ? j.ads.map((a: any) => ({
    adId: String(a?.ad_id ?? ""),
    campaignId: String(a?.campaign_id ?? ""),
    text: String(a?.title_text ?? ""),
    clickUrl: typeof a?.click_url === "string" ? a.click_url : "",
    bannerEnabled: a?.banner_enabled === true,
  })) : [];
  return {
    lifetimeUsd: num(b.lifetime_usd),
    todayUsd: num(b.today_usd),
    ads,
    viewThresholdSeconds: typeof j?.view_threshold_seconds === "number"
      ? j.view_threshold_seconds : null,
    kill: j?.kill === true,
  };
}

export function parseEarnings(j: any): Earnings {
  const c = j?.cap;
  let cap: Cap | null = null;
  if (c && (c.scope === "hourly" || c.scope === "daily")
      && typeof c.cap_usd !== "undefined" && typeof c.reset_seconds === "number") {
    cap = { scope: c.scope, capUsd: num(c.cap_usd), resetSeconds: Math.max(0, Math.floor(c.reset_seconds)) };
  }
  return { cap };
}

export interface ApiDeps {
  fetch: typeof fetch;
  token: string;
  base: string;
  ccVersion: string;
}

export async function fetchPortfolio(d: ApiDeps): Promise<Portfolio> {
  const url = `${d.base}/v1/portfolio?claude_code_version=${encodeURIComponent(d.ccVersion)}`;
  const r = await d.fetch(url, { headers: { authorization: `Bearer ${d.token}` } });
  if (!r.ok) throw new Error(`portfolio HTTP ${r.status}`);
  return parsePortfolio(await r.json());
}

export async function fetchEarnings(d: ApiDeps): Promise<Earnings> {
  const r = await d.fetch(`${d.base}/v1/earnings`, { headers: { authorization: `Bearer ${d.token}` } });
  if (!r.ok) throw new Error(`earnings HTTP ${r.status}`);
  return parseEarnings(await r.json());
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd kicker && bun test test/api.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd kicker && git add -A && git commit -m "feat: api client with pure parsers (read-only)"
```

---

## Task 4: Derivations (pure history math)

**Files:**
- Create: `kicker/src/derive.ts`
- Test: `kicker/test/derive.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// kicker/test/derive.test.ts
import { test, expect } from "bun:test";
import { ratePerHour, projectSecondsToCap, isStalled, fmtUsd, fmtDuration } from "../src/derive";
import type { Sample } from "../src/types";

const s = (ts: number, todayUsd: number): Sample =>
  ({ ts, todayUsd, lifetimeUsd: todayUsd, adId: "a", kill: false });

test("ratePerHour computes $/hr over the window", () => {
  const samples = [s(0, 0), s(3_600_000, 0.5)]; // +$0.50 over 1h
  expect(ratePerHour(samples)).toBeCloseTo(0.5, 5);
});

test("ratePerHour is 0 with <2 samples or no gain", () => {
  expect(ratePerHour([s(0, 1)])).toBe(0);
  expect(ratePerHour([s(0, 1), s(3_600_000, 1)])).toBe(0);
});

test("projectSecondsToCap returns remaining/rate", () => {
  expect(projectSecondsToCap(0.5, 1.0, 0.5)).toBeCloseTo(3600, 5); // $0.50 left at $0.50/h
  expect(projectSecondsToCap(1.0, 1.0, 0.5)).toBe(0);              // already at cap
  expect(projectSecondsToCap(0.5, 1.0, 0)).toBeNull();            // no rate → unknown
});

test("isStalled true when active and today flat across window", () => {
  const now = 1_000_000;
  const samples = [s(now - 600_000, 0.4), s(now - 60_000, 0.4)];
  expect(isStalled({ samples, now, windowMs: 300_000, active: true })).toBe(true);
});

test("isStalled false when inactive or earnings moved", () => {
  const now = 1_000_000;
  const flat = [s(now - 600_000, 0.4), s(now - 60_000, 0.4)];
  expect(isStalled({ samples: flat, now, windowMs: 300_000, active: false })).toBe(false);
  const moved = [s(now - 600_000, 0.4), s(now - 60_000, 0.5)];
  expect(isStalled({ samples: moved, now, windowMs: 300_000, active: true })).toBe(false);
});

test("formatters", () => {
  expect(fmtUsd(1.5)).toBe("$1.50");
  expect(fmtDuration(3661)).toBe("1h1m");
  expect(fmtDuration(45)).toBe("45s");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd kicker && bun test test/derive.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `kicker/src/derive.ts`**

```ts
import type { Sample } from "./types";

/** Average $/hr of today_usd growth across the provided samples (sorted or not).
 *  Returns 0 with <2 samples, no positive gain, or a zero time span. A midday
 *  reset (today_usd drops) yields 0 for that window — acceptable for a rate hint. */
export function ratePerHour(samples: Sample[]): number {
  if (samples.length < 2) return 0;
  const sorted = [...samples].sort((a, b) => a.ts - b.ts);
  const first = sorted[0]!, last = sorted[sorted.length - 1]!;
  const hours = (last.ts - first.ts) / 3_600_000;
  if (hours <= 0) return 0;
  const gain = last.todayUsd - first.todayUsd;
  return gain > 0 ? gain / hours : 0;
}

/** Seconds until today_usd reaches capUsd at ratePerHour. null when rate is 0
 *  (unknown), 0 when already at/over the cap. */
export function projectSecondsToCap(todayUsd: number, capUsd: number, rate: number): number | null {
  if (rate <= 0) return null;
  const remaining = capUsd - todayUsd;
  if (remaining <= 0) return 0;
  return (remaining / rate) * 3600;
}

export interface StallInput {
  samples: Sample[];
  now: number;
  windowMs: number;
  active: boolean;
}

/** True when the user is actively coding but today_usd hasn't moved across the
 *  recent window — the silent-injection-broke signal. */
export function isStalled({ samples, now, windowMs, active }: StallInput): boolean {
  if (!active) return false;
  const recent = samples.filter((s) => s.ts >= now - windowMs && s.ts <= now);
  if (recent.length < 2) return false;
  const min = Math.min(...recent.map((s) => s.todayUsd));
  const max = Math.max(...recent.map((s) => s.todayUsd));
  return max - min === 0;
}

export const fmtUsd = (n: number): string => `$${(Number.isFinite(n) ? n : 0).toFixed(2)}`;

export function fmtDuration(sec: number): string {
  sec = Math.max(0, Math.floor(sec));
  if (sec >= 3600) return `${Math.floor(sec / 3600)}h${Math.floor((sec % 3600) / 60)}m`;
  if (sec >= 60) return `${Math.floor(sec / 60)}m`;
  return `${sec}s`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd kicker && bun test test/derive.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
cd kicker && git add -A && git commit -m "feat: pure history derivations (rate, projection, stall, formatters)"
```

---

## Task 5: SQLite history store

**Files:**
- Create: `kicker/src/store.ts`
- Test: `kicker/test/store.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// kicker/test/store.test.ts
import { test, expect } from "bun:test";
import { openStore } from "../src/store";

test("insert + latest + recentSince round-trip", () => {
  const store = openStore(":memory:");
  store.insertSample({ ts: 1000, lifetimeUsd: 1, todayUsd: 0.1, adId: "a", kill: false });
  store.insertSample({ ts: 2000, lifetimeUsd: 1.2, todayUsd: 0.2, adId: "b", kill: false });
  expect(store.latest()?.todayUsd).toBe(0.2);
  expect(store.recentSince(1500).length).toBe(1);
  expect(store.recentSince(0).length).toBe(2);
});

test("latest returns null on empty store", () => {
  expect(openStore(":memory:").latest()).toBeNull();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd kicker && bun test test/store.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `kicker/src/store.ts`**

```ts
import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { Sample } from "./types";

export interface Store {
  insertSample(s: Sample): void;
  latest(): Sample | null;
  recentSince(ts: number): Sample[];
  close(): void;
}

export function openStore(path: string): Store {
  if (path !== ":memory:") { try { mkdirSync(dirname(path), { recursive: true }); } catch {} }
  const db = new Database(path);
  db.run(`CREATE TABLE IF NOT EXISTS samples (
    ts INTEGER PRIMARY KEY, lifetime_usd REAL, today_usd REAL, ad_id TEXT, kill INTEGER
  )`);
  const rowToSample = (r: any): Sample => ({
    ts: r.ts, lifetimeUsd: r.lifetime_usd, todayUsd: r.today_usd,
    adId: r.ad_id, kill: !!r.kill,
  });
  return {
    insertSample(s) {
      db.run("INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?)",
        [s.ts, s.lifetimeUsd, s.todayUsd, s.adId, s.kill ? 1 : 0]);
    },
    latest() {
      const r = db.query("SELECT * FROM samples ORDER BY ts DESC LIMIT 1").get() as any;
      return r ? rowToSample(r) : null;
    },
    recentSince(ts) {
      return (db.query("SELECT * FROM samples WHERE ts >= ? ORDER BY ts ASC").all(ts) as any[])
        .map(rowToSample);
    },
    close() { db.close(); },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd kicker && bun test test/store.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd kicker && git add -A && git commit -m "feat: bun:sqlite history store"
```

---

## Task 6: Auth (OAuth state flow + token file)

**Files:**
- Create: `kicker/src/auth.ts`
- Test: `kicker/test/auth.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// kicker/test/auth.test.ts
import { test, expect } from "bun:test";
import { startLogin, pollOnce, refresh } from "../src/auth";

const base = "https://b";

test("startLogin parses location + state from the 307", async () => {
  const fakeFetch = async () => new Response(null, {
    status: 307,
    headers: { location: "https://accounts.google.com/o/oauth2/v2/auth?state=XYZ" },
  });
  const r = await startLogin({ fetch: fakeFetch as any, base });
  expect(r.state).toBe("XYZ");
  expect(r.url).toContain("accounts.google.com");
});

test("pollOnce returns tokens when access_token present, else null", async () => {
  const withTokens = async () => new Response(JSON.stringify({ access_token: "AT", refresh_token: "RT" }), { status: 200 });
  const empty = async () => new Response(JSON.stringify({}), { status: 200 });
  expect(await pollOnce({ fetch: withTokens as any, base }, "S")).toEqual({ access_token: "AT", refresh_token: "RT" });
  expect(await pollOnce({ fetch: empty as any, base }, "S")).toBeNull();
});

test("refresh posts the refresh_token and returns new tokens", async () => {
  let body = "";
  const fakeFetch = async (_url: string, init: any) => { body = init.body;
    return new Response(JSON.stringify({ access_token: "AT2", refresh_token: "RT2" }), { status: 200 }); };
  const t = await refresh({ fetch: fakeFetch as any, base }, "RT1");
  expect(JSON.parse(body)).toEqual({ refresh_token: "RT1" });
  expect(t?.access_token).toBe("AT2");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd kicker && bun test test/auth.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `kicker/src/auth.ts`**

```ts
import { readFileSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { dirname } from "node:path";
import { AUTH_FILE } from "./config";
import type { Tokens } from "./types";

export interface AuthDeps { fetch: typeof fetch; base: string; }

export async function startLogin(d: AuthDeps): Promise<{ url: string; state: string }> {
  const r = await d.fetch(`${d.base}/v1/auth/extension/start`, { redirect: "manual" });
  const loc = r.headers.get("location");
  if (!loc) throw new Error("no redirect from /start (need Bun/Node ≥18)");
  const state = new URL(loc).searchParams.get("state");
  if (!state) throw new Error("no state in redirect URL");
  return { url: loc, state };
}

export async function pollOnce(d: AuthDeps, state: string): Promise<Tokens | null> {
  const r = await d.fetch(`${d.base}/v1/auth/extension/poll?state=${encodeURIComponent(state)}`);
  const j: any = await r.json().catch(() => ({}));
  return j?.access_token ? { access_token: j.access_token, refresh_token: j.refresh_token } : null;
}

export async function refresh(d: AuthDeps, refreshToken: string): Promise<Tokens | null> {
  const r = await d.fetch(`${d.base}/v1/auth/refresh`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!r.ok) return null;
  const j: any = await r.json().catch(() => ({}));
  return j?.access_token ? { access_token: j.access_token, refresh_token: j.refresh_token } : null;
}

// --- token file (chmod 600). Keychain storage is a Plan 3+ enhancement. ---
export function loadTokens(): Tokens | null {
  try { return JSON.parse(readFileSync(AUTH_FILE, "utf8")); } catch { return null; }
}
export function saveTokens(t: Tokens): void {
  try { mkdirSync(dirname(AUTH_FILE), { recursive: true, mode: 0o700 }); } catch {}
  writeFileSync(AUTH_FILE, JSON.stringify(t, null, 2) + "\n", { mode: 0o600 });
}
export function clearTokens(): void { try { rmSync(AUTH_FILE); } catch {} }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd kicker && bun test test/auth.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd kicker && git add -A && git commit -m "feat: auth state-flow + token file storage"
```

---

## Task 7: CLI wiring (text output) + manual smoke test

**Files:**
- Create: `kicker/src/cli.ts`
- Create: `kicker/README.md`

- [ ] **Step 1: Write `kicker/src/cli.ts`**

```ts
#!/usr/bin/env bun
import { BASE, CC_VERSION, DB_FILE } from "./config";
import { startLogin, pollOnce, refresh, loadTokens, saveTokens, clearTokens } from "./auth";
import { fetchPortfolio, fetchEarnings } from "./api";
import { openStore } from "./store";
import { ratePerHour, projectSecondsToCap, fmtUsd, fmtDuration } from "./derive";
import { spawn } from "node:child_process";
import type { Tokens, Portfolio } from "./types";

const deps = (token: string) => ({ fetch, token, base: BASE, ccVersion: CC_VERSION });

function openBrowser(url: string) {
  const cmd = process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open";
  try { spawn(cmd, [url], { stdio: "ignore", detached: true }).unref(); } catch {}
}

async function withToken(): Promise<Tokens> {
  const t = loadTokens();
  if (!t) { console.error("Not signed in. Run: kicker login"); process.exit(1); }
  return t;
}

// GET with auto-refresh on 401 (refresh consumes the CLI's own rotating token).
async function authed<T>(call: (token: string) => Promise<T>): Promise<T> {
  const t = await withToken();
  try { return await call(t.access_token); }
  catch (e: any) {
    if (!String(e?.message).includes("HTTP 401") || !t.refresh_token) throw e;
    const nt = await refresh({ fetch, base: BASE }, t.refresh_token);
    if (!nt) { console.error("Session expired. Run: kicker login"); process.exit(1); }
    saveTokens({ ...t, ...nt });
    return call(nt.access_token);
  }
}

function recordSample(p: Portfolio) {
  const store = openStore(DB_FILE);
  store.insertSample({ ts: Date.now(), lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd,
    adId: p.ads[0]?.adId ?? "", kill: p.kill });
  return store;
}

async function cmdLogin() {
  const { url, state } = await startLogin({ fetch, base: BASE });
  console.log("\n  Sign in with Google:\n\n    " + url + "\n");
  openBrowser(url);
  process.stdout.write("  waiting");
  for (let i = 0; i < 120; i++) {
    await new Promise((r) => setTimeout(r, 1500));
    process.stdout.write(".");
    const t = await pollOnce({ fetch, base: BASE }, state).catch(() => null);
    if (t) { saveTokens(t); console.log("\n\n  ✓ signed in.\n"); return; }
  }
  console.error("\n\n  timed out.\n"); process.exit(1);
}

async function cmdPortfolio() {
  const p = await authed((tk) => fetchPortfolio(deps(tk)));
  const store = recordSample(p);
  const since = store.recentSince(Date.now() - 6 * 3_600_000);
  const rate = ratePerHour(since);
  console.log("\n  Kicker — portfolio");
  console.log("  " + "-".repeat(40));
  console.log(`  Balance   ${fmtUsd(p.lifetimeUsd)} lifetime  ·  ${fmtUsd(p.todayUsd)} today`);
  if (rate > 0) console.log(`  Rate      ${fmtUsd(rate)}/hr (last 6h)`);
  console.log(`  Killswitch ${p.kill ? "ON" : "off"}   View gate ${p.viewThresholdSeconds ?? "?"}s`);
  console.log(`\n  Served ads (${p.ads.length})`);
  p.ads.forEach((a, i) => console.log(`   ${i + 1}. ${a.text}${a.clickUrl ? "  → " + a.clickUrl : ""}`));
  console.log("");
}

async function cmdEarnings() {
  const [p, e] = await Promise.all([
    authed((tk) => fetchPortfolio(deps(tk))),
    authed((tk) => fetchEarnings(deps(tk))),
  ]);
  const rate = ratePerHour(openStore(DB_FILE).recentSince(Date.now() - 6 * 3_600_000));
  console.log("\n  Earnings");
  console.log(`  lifetime ${fmtUsd(p.lifetimeUsd)}  ·  today ${fmtUsd(p.todayUsd)}`);
  if (e.cap) {
    console.log(`  cap      ${e.cap.scope} ${fmtUsd(e.cap.capUsd)} (resets ${fmtDuration(e.cap.resetSeconds)})`);
    const eta = projectSecondsToCap(p.todayUsd, e.cap.capUsd, rate);
    if (eta !== null) console.log(`  to cap   ~${fmtDuration(eta)} at current rate`);
  }
  console.log("");
}

function cmdStatus() {
  const t = loadTokens();
  console.log("\n  kicker status");
  console.log("  backend    " + BASE);
  console.log("  signed in  " + (t ? "yes" : "no"));
  console.log("  history db " + DB_FILE + "\n");
}

const cmd = (process.argv[2] || "portfolio").toLowerCase();
const table: Record<string, () => unknown> = {
  login: cmdLogin, portfolio: cmdPortfolio, earnings: cmdEarnings,
  status: cmdStatus, logout: () => { clearTokens(); console.log("signed out."); },
};
const fn = table[cmd];
if (!fn) { console.error("commands: login | portfolio | earnings | status | logout"); process.exit(2); }
await (async () => fn())().catch((e: any) => { console.error("error:", e?.message ?? e); process.exit(1); });
```

- [ ] **Step 2: Create `kicker/README.md`**

```markdown
# Kicker

Read-only CLI for your own Kickbacks.ai earnings. Not affiliated with Kickbacks.ai / ShiftKeys, Inc.

```bash
bun run src/cli.ts login        # Google sign-in (own session)
bun run src/cli.ts              # portfolio (default)
bun run src/cli.ts earnings
bun run src/cli.ts status
```

Never sends billing events — only reads `/v1/portfolio` and `/v1/earnings`.
```

- [ ] **Step 3: Verify the whole suite passes**

Run: `cd kicker && bun test`
Expected: PASS (all tests from Tasks 3–6, 15 total).

- [ ] **Step 4: Smoke-test commands that need no auth**

Run: `cd kicker && bun run src/cli.ts status`
Expected: prints status with "signed in  no".

- [ ] **Step 5: Manual auth smoke test (human-in-the-loop)**

Run: `cd kicker && bun run src/cli.ts login` then `bun run src/cli.ts`
Expected: browser opens to Google; after sign-in, `portfolio` prints your real balances.
⚠️ This is the single-session check from Task 0 Step 3 — afterward, confirm the VS Code extension is still signed in. Record the result in the design doc §13.5.

- [ ] **Step 6: Commit**

```bash
cd kicker && git add -A && git commit -m "feat: kicker CLI (login/portfolio/earnings/status/logout)"
```

---

## Self-Review

**Spec coverage (design doc §4 P0 + §5 core):** login ✅ (Task 6/7), portfolio + earnings + status + logout ✅ (Task 7), API client ✅ (Task 3), SQLite history ✅ (Task 5), rate/projection derivations ✅ (Task 4), read-only/no-metrics ✅ (only portfolio/earnings/auth calls exist). OpenTUI, poller/watchdog, Swift menu, brew — explicitly deferred to Plans 2–5.

**Placeholder scan:** none — every step has runnable code or an exact command + expected output.

**Type consistency:** `Tokens`/`Portfolio`/`Sample`/`Cap` defined in Task 2 are used unchanged in Tasks 3–7. `openStore`/`insertSample`/`latest`/`recentSince` consistent (Task 5 → Task 7). `ratePerHour`/`projectSecondsToCap`/`fmtUsd`/`fmtDuration` consistent (Task 4 → Task 7). `startLogin`/`pollOnce`/`refresh`/`loadTokens`/`saveTokens`/`clearTokens` consistent (Task 6 → Task 7). `ApiDeps`/`AuthDeps` injected uniformly.

**Open item surfaced for execution:** Task 7 Step 5 is the empirical single-session auth test that resolves design §13.5; record the outcome there.
