# Kickbacks — Plan 2: OpenTUI `watch` dashboard

> **For agentic workers:** implement task-by-task with TDD. Steps use `- [ ]`. Live in `cli/`. Commit per task on `main` (project convention).

**Goal:** Add `kickbacks watch` — a live, framed OpenTUI dashboard that auto-refreshes earnings, renders the §15.2 model (state badge · today/lifetime · rate · cap bar · projection · sparkline · served ad), records a history sample each refresh, and quits on `q`/Ctrl-C. Default `kickbacks` and the other commands are unchanged.

**Decisions (locked 2026-06-13):**
- **OpenTUI core (imperative) API** — first runtime dep (`@opentui/core`); no React/Solid. Verified: loads under `bun build --compile` (Task 0 spike).
- **`watch` is the only live TUI**; default `kickbacks` keeps the static colored renderer (also the non-TTY/piped fallback). Non-TTY `watch` falls back to one static render.

**Architecture:** A pure data layer (`loadModel`) and a pure-ish view builder (`buildDashboardTree`) — both testable headless via `@opentui/core/testing` + the existing mock-backend pattern — under a thin imperative controller (`runWatch`) that owns the renderer, the refresh timer, and key input. The 401→refresh→retry logic is extracted from `cli.ts` into a reusable `makeAuthedRunner` (throws `AuthError`) so both the one-shot CLI (catches → exit) and the TUI (catches → show + destroy) share it.

**Tech:** Bun, `@opentui/core`, `bun:sqlite`, existing `api`/`auth`/`store`/`derive`/`ui`.

---

## File Structure

```
cli/
  package.json          # + dependency: @opentui/core
  src/
    auth.ts             # + makeAuthedRunner / AuthError (extracted 401-refresh)
    ui.ts               # + sparkline() (pure)
    tui.ts              # NEW — WatchModel, loadModel (DI), buildDashboardTree (OpenTUI tree)
    watch.ts            # NEW — runWatch controller (renderer, timer, keys); not unit-tested
    cli.ts              # authed() now wraps makeAuthedRunner; + `watch` command + non-TTY fallback
  test/
    ui.test.ts          # + sparkline tests
    tui.test.ts         # NEW — loadModel (mock fetch) + buildDashboardTree snapshot/content
```

`tui.ts` (data + view, testable) is separate from `watch.ts` (imperative lifecycle, manual QA). The Swift app (Plan 4) will read the same SQLite store, not this code.

---

## Task 0 — De-risk (DONE 2026-06-13)

- [x] `@opentui/core@0.4.1` installs; `bun run` loads the native addon.
- [x] `bun build --compile` produces a binary that **runs and loads** the addon (`loaded function function function`). ~66 MB binary (Plan 5/Homebrew note).
- Caveat: actual TTY rendering verified via `createTestRenderer` snapshots (headless) + a manual run in a real terminal (for the user; can't drive a live alt-screen TTY in CI).

---

## Task 1 — `sparkline()` in `ui.ts`

**Files:** Modify `cli/src/ui.ts`, `cli/test/ui.test.ts`.

- [ ] **Step 1: failing test** (`ui.test.ts`):
```ts
import { sparkline } from "../src/ui";
test("sparkline maps values across the block ramp", () => {
  expect(sparkline([0, 1, 2, 3, 4, 5, 6, 7])).toBe("▁▂▃▄▅▆▇█");
  expect(sparkline([5, 5, 5])).toBe("▅▅▅");      // flat → mid band, never empty
  expect(sparkline([])).toBe("");
  expect(sparkline([1])).toBe("█");               // single point → max
});
```
- [ ] **Step 2:** `bun test test/ui.test.ts` → FAIL (sparkline not a function).
- [ ] **Step 3:** implement in `ui.ts`:
```ts
const SPARKS = "▁▂▃▄▅▆▇█";
/** Map numbers to an 8-level block sparkline. Flat series sits mid-band; empty → "". */
export function sparkline(values: number[]): string {
  if (values.length === 0) return "";
  if (values.length === 1) return SPARKS[SPARKS.length - 1]!;
  const min = Math.min(...values), max = Math.max(...values);
  const span = max - min;
  return values.map((v) => {
    const level = span === 0 ? Math.floor(SPARKS.length / 2) : Math.round(((v - min) / span) * (SPARKS.length - 1));
    return SPARKS[level]!;
  }).join("");
}
```
- [ ] **Step 4:** `bun test test/ui.test.ts` → PASS.
- [ ] **Step 5:** commit `feat(ui): add sparkline()`.

---

## Task 2 — `makeAuthedRunner` / `AuthError` in `auth.ts` (extract for reuse)

**Files:** Modify `cli/src/auth.ts`, `cli/src/cli.ts`. (No new test file; covered by existing `cli.integration.test.ts` 401 path.)

- [ ] **Step 1:** add to `auth.ts` (imports `HttpError` from `./api`):
```ts
import { HttpError } from "./api";

export class AuthError extends Error {
  constructor(message: string) { super(message); this.name = "AuthError"; }
}

/** Runs an authed call, refreshing + retrying once on 401. Throws AuthError when
 *  there is no token or the refresh fails — the caller decides whether to exit
 *  (one-shot CLI) or show it and clean up (the TUI). No process side-effects. */
export function makeAuthedRunner(d: AuthDeps) {
  return async function run<T>(call: (token: string) => Promise<T>): Promise<T> {
    const t = loadTokens();
    if (!t) throw new AuthError("Not signed in. Run: kickbacks login");
    try { return await call(t.access_token); }
    catch (e) {
      if (!(e instanceof HttpError) || e.status !== 401 || !t.refresh_token) throw e;
      const nt = await refresh(d, t.refresh_token);
      if (!nt) throw new AuthError("Session expired. Run: kickbacks login");
      saveTokens({ ...t, ...nt });
      return call(nt.access_token);
    }
  };
}
```
- [ ] **Step 2:** refactor `cli.ts` — replace `withToken` + `authed` with:
```ts
import { makeAuthedRunner, AuthError, loadTokens, saveTokens, clearTokens, startLogin, pollOnce, signout } from "./auth";
const runAuthed = makeAuthedRunner({ fetch, base: BASE });
async function authed<T>(call: (token: string) => Promise<T>): Promise<T> {
  try { return await runAuthed(call); }
  catch (e) {
    if (e instanceof AuthError) { console.error(e.message); process.exit(1); }
    throw e;
  }
}
```
(Delete the old `withToken`; behavior — "Not signed in"/"Session expired" → exit 1 — is preserved.)
- [ ] **Step 3:** `bun test test/cli.integration.test.ts` → PASS (the 401-refresh test still green; "Not signed in" path unchanged).
- [ ] **Step 4:** `bunx --bun tsc --noEmit` → clean.
- [ ] **Step 5:** commit `refactor(auth): extract makeAuthedRunner/AuthError for CLI + TUI reuse`.

---

## Task 3 — `WatchModel` + `loadModel` in `tui.ts`

**Files:** Create `cli/src/tui.ts`; Create `cli/test/tui.test.ts`.

- [ ] **Step 1: failing test** (`tui.test.ts`) — `loadModel` orchestrates fetch+record+derive with injected fns + an in-memory store:
```ts
import { test, expect } from "bun:test";
import { loadModel } from "../src/tui";
import { openStore } from "../src/store";
import type { Portfolio, Earnings } from "../src/types";

const P: Portfolio = { lifetimeUsd: 12.34, todayUsd: 0.56, viewThresholdSeconds: 15, kill: false,
  ads: [{ adId: "552e20ec", campaignId: "23f8444b", text: "Inflowpay", clickUrl: "https://x.test", bannerEnabled: true }] };
const E: Earnings = { cap: { scope: "daily", capUsd: 1, resetSeconds: 15120 } };

test("loadModel fetches, records a sample, and derives state", async () => {
  const store = openStore(":memory:");
  const m = await loadModel({
    fetchPortfolio: async () => P,
    fetchEarnings: async () => E,
    store, now: 1_000_000,
  });
  expect(m.p.todayUsd).toBe(0.56);
  expect(m.e?.cap?.scope).toBe("daily");
  expect(m.state).toBe("earning");
  expect(store.latest()?.todayUsd).toBe(0.56);   // sample recorded
  expect(m.samples.length).toBe(1);
});

test("loadModel tolerates an earnings failure (cap optional)", async () => {
  const store = openStore(":memory:");
  const m = await loadModel({
    fetchPortfolio: async () => P,
    fetchEarnings: async () => { throw new Error("boom"); },
    store, now: 1_000_000,
  });
  expect(m.e).toBeNull();
  expect(m.p.todayUsd).toBe(0.56);
});
```
- [ ] **Step 2:** `bun test test/tui.test.ts` → FAIL (module not found).
- [ ] **Step 3:** create `tui.ts` (data half):
```ts
import type { Portfolio, Earnings, Sample } from "./types";
import type { Store } from "./store";
import { ratePerHour, earningState, type EarningState } from "./derive";

export interface WatchModel {
  p: Portfolio; e: Earnings | null; rate: number; state: EarningState; samples: Sample[]; ts: number;
}

export interface LoadDeps {
  fetchPortfolio: () => Promise<Portfolio>;
  fetchEarnings: () => Promise<Earnings>;
  store: Store;
  now: number;
}

/** Fetch portfolio (required) + earnings (optional), record a sample, derive rate/state. */
export async function loadModel(d: LoadDeps): Promise<WatchModel> {
  const p = await d.fetchPortfolio();
  const e = await d.fetchEarnings().catch(() => null);
  d.store.insertSample({ ts: d.now, lifetimeUsd: p.lifetimeUsd, todayUsd: p.todayUsd,
    adId: p.ads[0]?.adId ?? "", kill: p.kill });
  const samples = d.store.recentSince(d.now - 24 * 3_600_000);
  return { p, e, rate: ratePerHour(samples), state: earningState(p, e), samples, ts: d.now };
}
```
- [ ] **Step 4:** `bun test test/tui.test.ts` → PASS (2 tests).
- [ ] **Step 5:** commit `feat(tui): WatchModel + loadModel (testable data layer)`.

---

## Task 4 — `buildDashboardTree` in `tui.ts` (OpenTUI view) + snapshot test

**Files:** Modify `cli/src/tui.ts`, `cli/test/tui.test.ts`.

- [ ] **Step 1: failing test** (append to `tui.test.ts`) — headless render via the test renderer:
```ts
import { createTestRenderer } from "@opentui/core/testing";
import { buildDashboardTree } from "../src/tui";

test("buildDashboardTree renders the unified model", async () => {
  const setup = await createTestRenderer({ width: 64, height: 20 });
  setup.renderer.root.add(buildDashboardTree(setup.renderer, {
    p: P, e: E, rate: 0.18, state: "earning", samples: [], ts: 0,
  }));
  await setup.renderOnce();
  const frame = setup.captureCharFrame();
  setup.renderer.destroy();
  expect(frame).toContain("kickbacks");
  expect(frame).toContain("Earning");
  expect(frame).toContain("$0.56");
  expect(frame).toContain("$12.34");
  expect(frame).toContain("Inflowpay");
});
```
- [ ] **Step 2:** `bun test test/tui.test.ts` → FAIL (buildDashboardTree not exported).
- [ ] **Step 3:** add to `tui.ts` (view half) — colors + a framed box of text rows:
```ts
import { BoxRenderable, TextRenderable, t, fg, type CliRenderer } from "@opentui/core";
import { fmtUsd, fmtDuration, projectSecondsToCap } from "./derive";
import { sparkline } from "./ui";

const COL = { green: "#3fb950", dim: "#6e7681", red: "#f85149", yellow: "#d29922", cyan: "#58a6ff", fg: "#c9d1d9" };
const BADGE: Record<EarningState, { glyph: string; label: string; color: string }> = {
  earning: { glyph: "●", label: "Earning", color: COL.green },
  killed: { glyph: "⊘", label: "Killswitch on", color: COL.red },
  cap: { glyph: "◐", label: "Cap reached", color: COL.yellow },
  "no-serve": { glyph: "○", label: "No ad serving", color: COL.dim },
};
const barGlyphs = (value: number, max: number, width = 14): string => {
  const filled = max > 0 ? Math.round(Math.max(0, Math.min(1, value / max)) * width) : 0;
  return "▰".repeat(filled) + "▱".repeat(Math.max(0, width - filled));
};

export function buildDashboardTree(renderer: CliRenderer, m: WatchModel): BoxRenderable {
  const b = BADGE[m.state];
  const box = new BoxRenderable(renderer, {
    id: "dash", border: true, borderStyle: "rounded", borderColor: b.color,
    padding: 1, flexDirection: "column", width: 62,
    title: ` kickbacks   ${b.glyph} ${b.label} `, titleAlignment: "left",
  });
  const line = (id: string, content: any) => box.add(new TextRenderable(renderer, { id, content, fg: COL.fg }));

  line("bal", t`${fg(COL.dim)("Today    ")}${fg(COL.green)(fmtUsd(m.p.todayUsd))}     ${fg(COL.dim)("Lifetime  ")}${fg(COL.green)(fmtUsd(m.p.lifetimeUsd))}`);
  if (m.rate > 0) line("rate", t`${fg(COL.dim)("Rate     ")}${fg(COL.green)(`${fmtUsd(m.rate)}/hr ▴`)}${fg(COL.dim)("  (last 6h)")}`);
  if (m.e?.cap) {
    const { capUsd, resetSeconds, scope } = m.e.cap;
    const pct = capUsd > 0 ? Math.min(100, Math.round((m.p.todayUsd / capUsd) * 100)) : 0;
    const label = scope.charAt(0).toUpperCase() + scope.slice(1);
    line("cap", t`${fg(COL.dim)(`${label} cap `)}${fg(COL.green)(barGlyphs(m.p.todayUsd, capUsd))}${fg(COL.dim)(`  ${pct}%  ·  ${fmtUsd(m.p.todayUsd)} / ${fmtUsd(capUsd)}  ·  resets ${fmtDuration(resetSeconds)}`)}`);
    const eta = projectSecondsToCap(m.p.todayUsd, capUsd, m.rate);
    if (eta !== null && eta > 0) line("eta", t`${fg(COL.dim)("Projected")} hits cap in ~${fmtDuration(eta)}`);
  }
  const spark = sparkline(m.samples.map((s) => s.todayUsd));
  line("spark", spark ? t`${fg(COL.dim)("24h       ")}${fg(COL.green)(spark)}` : t`${fg(COL.dim)("24h        collecting history…")}`);
  const ad = m.p.ads[0];
  line("ad", ad ? t`${fg(COL.cyan)(" ▸ ")}${ad.text}${ad.clickUrl ? fg(COL.dim)(`  ↗ ${ad.clickUrl}`) : ""}` : t`${fg(COL.dim)('   (no ad serving — "your ad here")')}`);
  line("keys", t`${fg(COL.dim)("r refresh · q quit")}`);
  return box;
}
```
- [ ] **Step 4:** `bun test test/tui.test.ts` → PASS (3 tests).
- [ ] **Step 5:** commit `feat(tui): OpenTUI dashboard tree builder + snapshot test`.

---

## Task 5 — `runWatch` controller in `watch.ts`

**Files:** Create `cli/src/watch.ts`. (No unit test — needs a TTY; verified by Task 4 snapshot + manual run.)

- [ ] **Step 1:** create `watch.ts`:
```ts
import { createCliRenderer, type KeyEvent } from "@opentui/core";
import { loadModel, buildDashboardTree, type WatchModel } from "./tui";
import { TextRenderable } from "@opentui/core";

export interface WatchDeps {
  load: (now: number) => Promise<WatchModel>;   // injected: does authed fetch + record + derive
  intervalMs: number;
  now: () => number;
}

/** Owns the renderer, the refresh timer, and key input. Rebuilds the tree each refresh
 *  (cheap at this cadence). `q`/Ctrl-C quit; `r` refreshes now. Errors render inline
 *  instead of crashing the terminal. */
export async function runWatch(d: WatchDeps): Promise<void> {
  const renderer = await createCliRenderer({ exitOnCtrlC: true });
  let current: any = null;

  const paint = (build: () => any) => {
    if (current) { renderer.root.remove(current); current.destroy?.(); }
    current = build();
    renderer.root.add(current);
    renderer.requestRender();
  };

  const refresh = async () => {
    try {
      const model = await d.load(d.now());
      paint(() => buildDashboardTree(renderer, model));
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      paint(() => new TextRenderable(renderer, { content: `  ${msg}\n  (q to quit)`, fg: "#f85149" }));
    }
  };

  renderer.keyInput.on("keypress", (k: KeyEvent) => {
    if (k.name === "q") renderer.destroy();
    else if (k.name === "r") void refresh();
  });

  const timer = setInterval(() => void refresh(), d.intervalMs);
  renderer.on("destroy", () => clearInterval(timer));
  await refresh(); // initial paint
}
```
- [ ] **Step 2:** `bunx --bun tsc --noEmit` → clean.
- [ ] **Step 3:** commit `feat(watch): runWatch controller (renderer, refresh timer, keys)`.

---

## Task 6 — Wire `watch` into the CLI + non-TTY fallback

**Files:** Modify `cli/src/cli.ts`, `cli/README.md`.

- [ ] **Step 1:** in `cli.ts`, add the command. `watch` interval via `KICKBACKS_WATCH_SECONDS` (default 30):
```ts
import { runWatch } from "./watch";

async function cmdWatch() {
  if (!process.stdout.isTTY) { await cmdPortfolio(); return; } // piped/non-TTY → one static render
  const seconds = Math.max(5, Number(process.env.KICKBACKS_WATCH_SECONDS) || 30);
  const store = openStore(DB_FILE);
  await runWatch({
    now: () => Date.now(),
    intervalMs: seconds * 1000,
    load: async (now) => loadModel({
      fetchPortfolio: () => runAuthed((tk) => fetchPortfolio(deps(tk))),
      fetchEarnings: () => runAuthed((tk) => fetchEarnings(deps(tk))),
      store, now,
    }),
  });
  store.close();
}
```
Add `loadModel` to the `./tui` import; `runAuthed` is the Task-2 runner. Register `watch: cmdWatch` in the dispatch table and add `watch` to the usage string.
- [ ] **Step 2:** `bunx --bun tsc --noEmit` → clean; `bun test` → all green (no regressions).
- [ ] **Step 3:** non-TTY smoke: `KICKBACKS_CONFIG_DIR=/tmp/kb-smoke bun run src/cli.ts watch | cat` → should error "Not signed in" (no token) and **not** hang (non-TTY fell back to one-shot). Expected exit non-zero, no alt-screen.
- [ ] **Step 4:** update `README.md` (root + `cli/`) — add `kickbacks watch` and `KICKBACKS_WATCH_SECONDS`.
- [ ] **Step 5:** commit `feat(cli): add 'watch' live dashboard command (+ non-TTY fallback)`.

---

## Task 7 — Review, manual QA handoff, docs

- [ ] **Step 1:** full `bun test` + `bunx tsc --noEmit` green.
- [ ] **Step 2:** compound-engineering review (TS + simplicity) over `tui.ts`/`watch.ts`/`cli.ts` diff; triage + apply.
- [ ] **Step 3:** **Manual QA (user, real terminal):** `cd cli && bun run src/cli.ts watch` after `login` → confirm the framed dashboard paints, refreshes, `r` refreshes, `q` quits cleanly (terminal restored). Record any issues.
- [ ] **Step 4:** update `docs/design.md` §15.2 note (static default + live `watch` shipped) and memory.

---

## Self-Review

**Spec coverage (design §15.2):** framed dashboard ✅ (Task 4), live refresh + `watch` ✅ (Tasks 5–6), state badge/cap/projection/ad ✅ (Task 4, reuses derive), sparkline ✅ (Task 1; sparse until Plan 3's poller — labeled "collecting…"), keys `r`/`q` ✅ (Task 5), non-TTY plain fallback ✅ (Task 6). `h` history-chart key — deferred (needs accumulated history; Plan 3).
**Placeholder scan:** none — every task has runnable code/commands.
**Type consistency:** `WatchModel`/`LoadDeps` (Task 3) consumed unchanged in Tasks 4–6; `makeAuthedRunner`/`AuthError` (Task 2) used in Task 6; `sparkline` (Task 1) used in Task 4.
**Reuse:** no business logic duplicated — `loadModel` composes existing `api`/`store`/`derive`; the TUI is a view over the same model the static renderer uses.
