# Menu-bar app redesign — stages, branding & history

**Date:** 2026-06-14
**Status:** Approved design (mockups validated via the brainstorming visual companion)
**Surface:** the Swift `KickbackBar` menu-bar app + supporting CLI (`kickback`) JSON commands

## Problem

The menu-bar app is a thin first cut. It renders the literal word `kickback` in the menu bar, and the dropdown shows the same rows in every state — there is no designed signed-out → login → data journey (a signed-out user just sees `$0.00` with no way to sign in). There is also no view onto the **local earnings history**, which is the one thing the official Kickbacks extension can't show.

## Goals

- A glanceable menu-bar label that shows live earnings: **`K$ <value>`**, tinted by state.
- A real **signed-out → signing-in → data** flow, with sign-in handled in-app.
- A complete, designed set of **states** (earning / stalled / capped / not-earning / idle / collecting / stale).
- A **History window** surfacing local past data (daily chart + totals), with honest **empty / not-enough-data** states.
- Keep the architecture: **the CLI is the single source of truth**; the Swift app renders JSON and manages only view/auth state.

## Non-goals

- No native Swift OAuth (we reuse `kickback login`; no duplicate auth path).
- No new network calls or write endpoints — still read-only (`/v1/portfolio`, `/v1/earnings` only).
- Not copying Kickbacks' logo artwork (see Branding).

## Branding

The user has chosen to lean into Kickbacks' visual identity (the app may eventually be offered to the Kickbacks team). Decisions:

- Menu bar and panel headers show **"K$" as plain text** (e.g., `K$ 12.34`). Format drops the redundant second `$` (write `K$ 12.34`, not `K$ $12.34`).
- The **app icon stays our own original cashback mark** (`app/Resources/AppIcon.*`).
- We do **not** reproduce Kickbacks' actual logo artwork. If the project is handed over, they drop in their official assets; Apache-2.0 already permits the handoff.
- The README "not affiliated" disclaimer stays until any such handover.

## Menu-bar label

The Swift app composes the label: `"K$ " + v`, where `v` is `model.menuValue` (the CLI emits today's earnings without the leading `$`, e.g. `12.34`, or `—` when signed out) — except while `authState == .signingIn`, when the app shows `…`. Color (set in Swift from `state`):

| State | Tint |
|---|---|
| earning | default (menu-bar foreground) |
| stalled | amber |
| capped | green |
| not-earning (killswitch) | red |
| idle / signed-out / signing-in | default / muted |

## Dropdown panel — states

The panel is one view that switches on `(authState, model.state)`. A colored **banner** (optional) + the data rows + a footer (`📊 History`, `↻ Refresh`, `⋯` overflow).

| # | State | Trigger | Content |
|---|---|---|---|
| a | Signed out | no tokens | "See your Kickbacks earnings" + **Sign in with Google** button |
| b | Signing in | app-managed, while `kickback login` runs | spinner, "Opening your browser…", Cancel |
| c | Earning | signed in, ads serving, not stalled | Today (large), 24h sparkline, Lifetime, Rate+trend, cap bar, "Now showing" ad |
| d | First run / collecting | signed in, < 2 samples | Today + live values; sparkline/rate replaced with "Collecting your trend…" |
| e | Stalled | active + today flat over stall window | amber banner, "flat 27m while active", last-earned |
| f | Capped | today ≥ cap | green banner, "cap reached — resets in …" |
| g | Not earning | `kill` true | red banner, "stopped or signed out in VS Code" |
| h | Idle / no ad | no ads serving, not killed | neutral banner, "no ad serving now" |
| i | Stale / offline | last fetch failed | dimmed values + "couldn't reach Kickbacks · showing data from Nm ago", Retry |

**Overflow (`⋯`):** Sign out · Start at login (toggle the `bar` LaunchAgent) · About · Quit.
**"Now showing":** lists all ads in rotation when there are several (today only the first is shown); the per-ad "earn after N s of viewing" uses `viewThresholdSeconds` as a tooltip/subtext.

## Login flow (background spawn)

1. Signed-out panel → **Sign in with Google**.
2. App sets `authState = .signingIn` and spawns the CLI login in the background (no Terminal window). The CLI opens the browser for Google consent and runs its local callback server.
3. App polls `kickback model --json` (~every 2s); when `signedIn` flips true, it resumes normal polling and shows the data panel.
4. Cancel / timeout (~2 min) / process exit without sign-in → back to signed-out with a brief error note.

**Open item to verify during build:** confirm `kickback login` completes when spawned without a TTY (it already opens a browser + runs a callback server, so it should). The CLI's current `cmdLogin` writes progress to stdout and auto-opens the browser; if any step needs a TTY, add a non-interactive/`--json` login mode. The app reads success via `model --json` (`signedIn`), so no CLI change may be required.

## History window

Opened from `📊 History` in the dropdown footer. A standalone window (SwiftUI `Window` scene; app stays `.accessory`). Fed by a **new `kickback history --json`** command so the app stays a pure renderer.

**Shows:** lifetime + since-install + days-tracked; a **daily $ bar chart** (7d / 14d / 30d / All toggle; amber bar = hit cap, bright = best day, outlined = today); tiles for **this week / this month / best day / avg per day**; a stats line for **days-hit-cap (last 7), campaigns seen, active hours**.

**States:**
- **Full** — enough days for the chart + tiles.
- **Not enough data** — show the days we have; dim the tiles we can't compute yet; amber note "Only N days tracked — weekly/monthly fill in as you keep earning."
- **Empty / day one** — dashed placeholder "No history yet — your first full day appears tomorrow," tiles show `—`, tip to keep the poller on.

## Data

**Live (already fetched):** today, lifetime, ads[] (text, clickUrl, campaignId), `viewThresholdSeconds`, `kill` (portfolio); cap {scope, capUsd, resetSeconds} (earnings). `viewThresholdSeconds`, the full ads list, and cap *scope* are newly surfaced.

**History (local SQLite `samples`):** every `kickback model`/`poll`/`portfolio` run records a sample (ts, lifetime, today, ad_id, kill; +active/cap on poller runs). The API exposes only today+lifetime, so all past views are derived locally and **accrue over time** — richest with the background poller running.

**New CLI command `kickback history --json`** emits:
- `lifetimeUsd`, `sinceInstallUsd`, `firstSampleTs`, `daysTracked`
- `daily`: `[{ date (local), usd, hitCap }]`
- `thisWeekUsd`, `thisMonthUsd`, `bestDay {date, usd}`, `avgPerDayUsd`
- `capHitsLast7`, `campaignsSeen` (distinct ad_id), `activeHours` (from `active` samples)

**New pure derivations (TS, unit-tested):** `dailyBuckets(samples, now)` (local-day boundaries; a day's earnings = max `today_usd` that day, falling back to lifetime delta), `summarize(daily, samples)` (totals/best/avg/since-install), `lastEarnedAt(samples)` (for stalled/not-earning "last earned …").

**MenuModel additions:** `menuValue` (today without the leading `$`, or `—`), `viewThresholdSeconds`, `ads: [{text,url}]`, `lastEarnedAgoSeconds`, and a `collecting` boolean (CLI sets it true when `< 2` samples, so the app shows the "collecting your trend" placeholder instead of an empty sparkline). Keep existing fields; `state` already covers killed/cap/stalled/no-serve/earning, with signed-out and idle existing.

## Architecture

- **CLI (TypeScript)** — owns all logic. Existing `model --json`; add `history --json`. New derivations in `derive.ts` (or a new `history.ts`). Read-only invariant preserved.
- **Swift app** — `KickbackKit` gains a `HistoryModel` DTO + a `history()` client call (mirrors `ModelClient.fetch()`). `KickbackBar`:
  - `MenuVM` adds an `authState` machine (`signedOut | signingIn | signedIn`) overlaid on the polled `MenuModel`; `signIn()` spawns login + polls; `signOut()` runs `kickback logout`.
  - `MenuContent` renders all panel states (a `Banner` view keyed by state; rows reused).
  - `HistoryWindow` + `HistoryVM` (fetches `history --json`, renders chart/tiles/empty states).
  - Menu-bar label = `model.menuLabel`, tint from `state`.

## Error handling

- Transient fetch failure → keep last model, show **Stale/offline** with age (current behavior keeps last model; add the age/affordance).
- Auth/refresh failure → **signed-out** (existing).
- CLI binary missing/spawn error → a clear "Can't reach the kickback CLI" panel (the bundled `.app` makes this rare).
- History command failure → History window shows the stale/empty state rather than crashing.

## Testing

- **TS unit tests:** `dailyBuckets` (day boundaries, midday reset, gaps/empty), `summarize` (week/month/best/avg/since-install, insufficient data), `lastEarnedAt`, `buildMenuModel` additions, `history --json` shape. (`bun test`, no network — inject samples/clock.)
- **Swift tests:** `authState` transitions; `menuLabel`/tint mapping per state; `HistoryModel` decode incl. empty/not-enough.
- **Manual QA (needs a human/TTY/GUI):** the background-spawn login round-trip; the History window open/resize; menu-bar tint changes; first-run "collecting" → populated.

## Rollout

Single coherent change to the app + CLI; build + install via the existing `scripts/install-app.sh`. No migration (schema unchanged; reuses existing `samples`/`kv`).
