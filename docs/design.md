# Kickbacks Companion — Design & Build Doc

**Name:** **Kicker** (CLI: `kicker`) — a "kicker" is a bonus/incentive payment; plays on "kickback" without being the trademark. _Not affiliated with Kickbacks.ai / ShiftKeys, Inc._
**Status:** Decisions locked (2026-06-13) — entering implementation
**Date:** 2026-06-13
**Scope:** A reliable, open-source, standalone **CLI + native macOS menu-bar app** for viewing and protecting your *own* Kickbacks.ai earnings — independent of VS Code and the extension.

### Decisions locked (2026-06-13)
- **Name:** Kicker (`kicker`). Neutral/non-affiliated framing; "not affiliated" disclaimer; email ShiftKeys before public share (§14.2).
- **Architecture:** TypeScript **core** (API client, Google OAuth, SQLite history, poller + stall watchdog) → **CLI** (TS + **OpenTUI**, Bun-compiled binary) + **menu bar** (native Swift `MenuBarExtra`, thin reader). Two languages bridged by a shared local SQLite store.
- **Distribution:** Homebrew **only** — a tap with a **formula** (CLI) + **cask** (menu app).
- **Posture:** read-only forever (never `/v1/metrics`); no subscription / no paid tier (§10).

> ⚠️ This tool talks to a **private, reverse-engineered API** and reads **your own account data only**. It is **read-only by construction** — it never posts billing/metric events. See §3 (the hard line) and §11 (risks).

---

## 1. Why build this

Today, the only window into your Kickbacks earnings is a single number in the VS Code status bar, and it only exists while VS Code + the `kickbacksai.kickbacks-ai` extension are running. That has three problems:

1. **No visibility when VS Code is closed.** Earnings accrue (or silently stop) with no ambient signal.
2. **No history.** The backend is amnesiac — it returns only "right now" (`lifetime_usd`, `today_usd`). There is no trend, rate, or projection.
3. **Silent failure.** When Claude Code or Codex updates, it clobbers the injected ad patch and earning stops — with no alert. The extension re-asserts on a timer, but you find out late.

A standalone companion fixes all three: ambient menu-bar presence, locally-accumulated history, and an active **stall watchdog**. It is also simply more *reliable* — it doesn't depend on an editor being open, and it degrades gracefully when the private API shifts.

---

## 2. What we're building on (the substrate)

Everything the backend exposes **read-only** (reverse-engineered from `kickbacksai.kickbacks-ai@0.3.177`; full contract in §6):

| Data | Source |
|---|---|
| `lifetime_usd`, `today_usd` | `GET /v1/portfolio` → `balances` |
| Currently-served ad(s) | `GET /v1/portfolio` → `ads[]` |
| `view_threshold_seconds`, `kill` | `GET /v1/portfolio` |
| Rate cap (`hourly`/`daily`, `cap_usd`, `reset_seconds`) | `GET /v1/earnings` |
| Local "what ad is showing now" | loopback `http://127.0.0.1:<port>/vibe-ads/<token>/ad` (only while VS Code runs) |

**The honest ceiling:** this is a *thin, read-only, single-user, unofficial* surface. There is **no** history/ledger/analytics endpoint (verified). That bounds what's possible:

- ❌ Not possible: a multi-user platform, server-backed analytics, anything that scales beyond "your own account."
- ✅ The opportunity: **the server forgets — so whoever samples and remembers wins.** A small local history layer turns two scalar dollar figures into trends, $/hour rate, cap projections, and anomaly alerts. That conversion is the entire product.

---

## 3. Goals & non-goals

**Goals**
- Reliable, standalone view of *your* earnings (works with VS Code closed).
- Ambient menu-bar presence on macOS.
- Local history → trends, rate, projections.
- **Stall/desync watchdog** — the feature that makes this more than a number-viewer.
- Open source, easy for others to run and contribute to.

**Non-goals (the hard line)**
- 🚫 **Never** `POST /v1/metrics` or fire any billing event. No fabricated impressions/clicks. This is an *observatory*, not a controller — that's also what keeps it cleanly legitimate.
- 🚫 No multi-user / hosted service.
- 🚫 No redistribution of Kickbacks' data or scraping of anyone else's account.

---

## 4. Product / features (prioritized)

**P0 — MVP**
- `login` (Google OAuth, the extension's `/v1/auth/extension/start` → poll flow), into the tool's **own** session.
- CLI: `portfolio` (default), `earnings`, `status`, `raw`, `logout`. *(We have a working prototype: `kb.mjs`.)*
- Menu-bar: today's earnings always visible; dropdown with lifetime, cap countdown, currently-served ad.

**P1 — the differentiators**
- **Local history**: sample every 2–5 min, store locally; sparkline + `$/hr` + "projected daily-cap hit in ~Xh."
- **Stall watchdog**: "signed in + actively coding, but `today_usd` flat for N min" → notify _"Kickbacks stopped earning — run Restore."_
- **Cap alerts**: notify on hourly/daily cap hit.

**P2 — nice-to-have**
- **Passive mode**: read the extension's loopback `/ad` + `/activity` + `~/.vibe-ads/*` with **no login** (works only while VS Code runs; zero auth risk) as a fallback/secondary source.
- Multi-surface ad inspector (CLI vs Claude Code vs Codex).
- History charts (week/month), best-earning-hours.
- CLI `watch` (live TUI) and `stall` (exit non-zero when stalled → scriptable).

---

## 5. Architecture

### Shape: shared core + thin clients + always-on poller

```
                ┌────────────────────────────────────────┐
                │              core library                │
                │  • API client (the fragile boundary)     │
                │  • OAuth (own session, token in Keychain)│
                │  • local history store (SQLite)          │
                │  • watchdog/alert logic                  │
                └───────┬───────────────┬──────────────────┘
                        │               │
        ┌───────────────▼──┐   ┌────────▼─────────┐   ┌──────────────────┐
        │   CLI (`kb`)     │   │ menu-bar app     │   │ poller (launchd) │
        │  reads core      │   │ reads core/store │   │ writes history,  │
        │                  │   │ ambient display  │   │ fires alerts 24/7│
        └──────────────────┘   └──────────────────┘   └──────────────────┘
```

The **poller** is what unlocks history + alerts — it must run even when neither client is open (a `launchd` user agent). The clients are thin readers of the local store; only the poller (and on-demand CLI/app refresh) hits the network.

### Auth modes
- **Authed (primary):** own Google-OAuth session, refresh token in macOS Keychain. Independent of the extension's token (see §11 single-session caveat).
- **Passive (fallback):** read loopback `/activity` + `~/.vibe-ads/*`; no login; only while VS Code runs.

### Local store (sketch)
```sql
CREATE TABLE samples (
  ts            INTEGER PRIMARY KEY,   -- unix ms
  lifetime_usd  REAL,
  today_usd     REAL,
  cap_scope     TEXT,                  -- hourly|daily
  cap_usd       REAL,
  cap_reset_s   INTEGER,
  kill          INTEGER,               -- 0/1
  ad_id         TEXT,
  active        INTEGER                -- was CC/Codex active (from transcript mtime/loopback)
);
```
Everything else (rate, projections, stall detection) is derived from this table.

### Language options & recommendation

| Option | Stack | Pros | Cons |
|---|---|---|---|
| **1 — Swift everything (recommended if the app is the star)** | One `KickbacksKit` Swift pkg → SwiftUI `MenuBarExtra` app + `swift-argument-parser` CLI + launchd agent | Truly native, tiny, no runtime, best Mac feel; **one core → native CLI *and* app**. Xcode 26.5 / Swift 6.3 already installed. | Abandons the Node CLI; no reuse for a future web dashboard. |
| **2 — TS core + Tauri** | `@kickbacks/core` (TS) → Node CLI + Tauri app + Node poller | One logic codebase (JS/TS); reuses `kb.mjs`; easy future web view. | Menu-bar less idiomatic than native; heavier; web-in-a-box. |
| **3 — Node-first, native later** | Harden `kb.mjs` + Node launchd poller now; thin Swift menu-bar reader later | Value fastest; lowest risk; incremental. | Straddles two languages. |

**Recommendation:** **Option 1 (Swift)** if the native menu-bar app is the centerpiece, or **Option 3** if you want a useful tool this week and native polish later. `kb.mjs` already proved the API either way.

---

## 6. API contract (foundation for contributors)

The single fragile boundary. Isolate it behind one module so an API change is a one-file fix.

| Endpoint | Method | Auth | Returns / body |
|---|---|---|---|
| `/v1/auth/extension/start` | GET (manual redirect) | none | `307` → Google OAuth URL w/ `state` |
| `/v1/auth/extension/poll?state=` | GET | none | `{access_token, refresh_token}` once consented |
| `/v1/auth/refresh` | POST | none | body `{refresh_token}` → `{access_token, refresh_token?}` (⚠️ rotates) |
| `/v1/auth/signout` | POST | none | body `{refresh_token}` |
| `/v1/portfolio?claude_code_version=&campaign=` | GET | Bearer | `{kill, balances{lifetime_usd,today_usd}, ads[{ad_id,campaign_id,title_text,icon_url,click_url,banner_enabled,session_token}], view_threshold_seconds}` |
| `/v1/earnings` | GET | Bearer | `{cap{scope,cap_usd,reset_seconds}, ...}` |
| `/v1/killswitch` | GET | Bearer | remote kill state |
| `/v1/me/consent` | GET/POST | Bearer | ToS version |

**Base:** `https://kickbacks-backend-gmdaqm2c7q-uw.a.run.app` (override-able). Reverse-engineered; **subject to change**.

---

## 7. Reliability (the "more reliable" promise)

- **Editor-independent:** runs without VS Code; the poller is a `launchd` agent.
- **Graceful degradation:** API drift → last-known values + clear status, never a crash. Fetch error ≠ "no serve."
- **Self-diagnosis:** a `doctor` command (token state, API reachability, extension presence, patch integrity).
- **The watchdog catches what the extension hides:** the extension fails *silently* on editor updates; the companion turns that into an alert. This is the core reliability win.

---

## 8. Open-source plan

- **License:** **Apache-2.0** (patent grant + explicit, good for a tool touching a third-party API) or **MIT** (simplest). Recommend Apache-2.0.
- **Naming / affiliation note:** "Kickbacks Companion" uses their mark. For an *unofficial* OSS tool, prefer a **distinct name** + an "*for Kickbacks.ai*" descriptor + a prominent **"not affiliated with Kickbacks.ai"** disclaimer. Candidates: `kb` (CLI) + app names like **Tally**, **Sidecar**, **Kickback HUD**, **Stash**. Decide in §13.
- **Repo layout — finalized 2026-06-13 (the locked hybrid):**
  ```
  kickbacks/        umbrella repo (companion project; tools branded "Kicker")
    docs/           this doc, API contract, plans, CONTRIBUTING
    cli/            Tool 1 — TS/Bun: shared core + `kicker` CLI + launchd poller
    app/            Tool 2 — Swift MenuBarExtra app (reads the shared store)   [Plan 4]
    packaging/      Homebrew tap: formula (cli) + cask (app)                   [Plan 5]
  ```
  The two tools are different languages, so they share **data, not code** — both read
  `~/.config/kicker/history.db`. The TS core lives in `cli/` (imported by the CLI and the
  poller); the Swift app is a thin reader of the store. _(The Swift-only Option-1 sketch is superseded.)_
- **Contribution surface:** the isolated API client. Document the contract (§6) so when Kickbacks changes an endpoint, a contributor fixes one file. Add issue/PR templates, semver, signed releases.
- **Security policy:** the tool handles OAuth tokens — store in Keychain, `chmod 600` for any file fallback, never log tokens, `SECURITY.md` for disclosure.

---

## 9. Community & support

- **GitHub Discussions** for Q&A; **issue templates** (bug / API-drift / feature).
- **`FUNDING.yml`** (GitHub Sponsors / Ko-fi / Open Collective).
- **Docs:** README quickstart, troubleshooting, the `doctor` command as first-line self-support.
- **Later:** a small Discord/Matrix if a community forms. Don't build it before there are users.
- **Build-in-public:** the reverse-engineering write-up is a natural launch artifact (HN/Reddit/newsletter) and a contributor magnet.

---

## 10. Earning / sustainability (honest)

**Market reality (checked 2026-06-13):** Kickbacks is **~9,071 installs**, 219★/49 forks, **2.5★** (5 ratings), and **pre-revenue** — payouts aren't open (Stripe "coming," $10 minimum) and there are no real advertisers yet (it seeds its own inventory). It is **proprietary**, owned by **ShiftKeys, Inc.** ("source-available, _not_ open source; no commercialization without written permission").

Two consequences: (a) **you can't out-monetize a host that doesn't pay yet** — balances are accruing funny-money, so chasing direct revenue now is premature; and (b) any *paid* companion would need ShiftKeys' written permission. **Decision: no subscription, no paid tier.** Optimize for trust, stars, and audience now; route money through a ShiftKeys partnership or a grown category later. The concrete support/outreach/launch plan is **§14**.

Calibrated to reality: this is a **niche tool**, so treat money as upside, not a plan. In rough order of how real it is:

1. **Protect & maximize your *own* Kickbacks income (most concrete).** The watchdog stops silent earning loss; ambient visibility nudges usage. The tool's clearest "earning for you" is making the income you *already* have via Kickbacks more reliable.
2. **Donations / sponsors.** GitHub Sponsors / Ko-fi (setup + copy in §14.1). Small but real for a useful dev tool with a good story.
3. **Referral funnel — UNVERIFIED.** A tool that helps people earn is a natural signup funnel, *if* Kickbacks has a referral/affiliate program. **None is exposed in the client API** (checked). Action: ask Kickbacks directly; if one exists, the "install Kickbacks to start earning" onboarding can carry your ref link.
4. **Partnership / sponsorship from ShiftKeys.** If this becomes the de-facto companion, the maker (Andrew McCalip / ShiftKeys, Inc.) may sponsor, bounty, or adopt it — possibly semi-official. Reaching out (outreach draft in §14.2) opens this door *and* de-risks the ToS question.
5. **Paid distribution / open-core (likely premature).** Mac App Store paid binary with open source ("free source, paid convenience"), or a pro tier (multi-account, cloud history sync). Only if a real audience appears.

> Realistic verdict: the dependable "source" is **(1) your protected Kickbacks income** plus maybe **(2) modest sponsors**. Everything else is upside that depends on adoption or a Kickbacks partnership.

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Private API drift** (endpoints/auth change) | Isolate the API client to one file; degrade gracefully; pin the extension version mirrored; contributors patch fast (§6). |
| **Auth single-session unknown** — an independent login *might* invalidate the extension's session | **Verify empirically first.** If it conflicts, default to **passive mode** (no login) or document the trade-off. |
| **ToS / affiliation** — private backend owned by **ShiftKeys, Inc.** (proprietary; no commercialization w/o written permission) | Frame as **read-only, personal-use**; don't redistribute their data; **email ShiftKeys/Andrew before any public share or paid use** (draft + sequencing in §14). |
| **Trademark / implying official** | Distinct name + "not affiliated" disclaimer (§8). |
| **Token security** | Keychain storage; `chmod 600` fallback; never log tokens; `SECURITY.md`. |
| **Scope creep into a "platform"** | Hard non-goals (§3); YAGNI; it stays a personal observatory. |

---

## 12. Roadmap (phases)

_These phases assume the incremental path (Option 3). Choosing **Option 1 (Swift-first)** collapses Phases 1 and 3 into a single Swift core + CLI + app built together, with the Node `kb.mjs` kept only as the API reference prototype._

- **Phase 0 — Spec** ← *this doc.*
- **Phase 1 — CLI hardened.** `kb.mjs` → real CLI (history sampling on-run, `doctor`, clean errors).
- **Phase 2 — Poller + history + watchdog.** launchd agent, SQLite, stall + cap alerts.
- **Phase 3 — Native menu-bar app.** SwiftUI `MenuBarExtra` reading the store; sparkline; ad inspector.
- **Phase 4 — Open-source polish.** License, name, README, CONTRIBUTING, FUNDING, release, launch post.

---

## 13. Open questions (decisions needed before/while building)

1. ✅ **Language path** — RESOLVED: TS core + TS/OpenTUI CLI + native Swift menu (hybrid; shared SQLite).
2. ✅ **App form** — RESOLVED: menu-bar first (lightest); optional history window later.
3. ◑ **Name + license** — Name = **Kicker**. License still open: **Apache-2.0** (recommended) vs MIT.
4. ◑ **Contact ShiftKeys** — YES, before any public share (draft in §14.2). Not yet sent.
5. ✅ **Auth default** — RESOLVED (2026-06-13): CLI `login` tested working end-to-end by the user; **authed (own-session) mode confirmed as the primary path**. Passive mode stays an optional P2 fallback, not needed for MVP.

---

## 14. Support, outreach & launch

**Decision: no subscription / no paid tier** (see §10). The plan is three lightweight, trust-first moves. **Sequence them: contact the host privately FIRST → then share on X; support links can go up anytime.** Posting publicly before a heads-up blindsides ShiftKeys and sours the relationship every monetization path depends on; a private heads-up first keeps the partnership door open *and* makes the public post stronger.

### 14.1 Support the maker (tips + stars)

A `.github/FUNDING.yml` makes GitHub render a **Sponsor** button on the repo:

```yaml
# .github/FUNDING.yml
github: [your-github-username]
ko_fi: your-kofi-handle            # or  buy_me_a_coffee: your-handle
custom: ["https://your-site.dev"]  # optional
```

README section:

> ## Support
> Free and open source. If it saves you from silently losing Kickbacks earnings, you can support development:
> - ❤️ Sponsor on GitHub · ☕ Tip on Ko-fi
> - ⭐ Or just star the repo — that genuinely helps it reach people.

Expectation: tips are coffee money. The compounding "support" is **stars + audience**, which is why 14.3 matters more than the tip jar.

### 14.2 Contact the host (ShiftKeys / Andrew McCalip) — FIRST

Send via a GitHub Discussion on `andrewmccalip/kickbacks.ai` or email. Constructive-ally tone, lead with value, low ask:

> **Subject: Built an open-source companion for Kickbacks — would love your blessing**
>
> Hi Andrew,
>
> I'm a Kickbacks user and like what you're building. I got curious how the extension works and ended up building a small **open-source, read-only** companion: a CLI + macOS menu-bar app that shows earnings outside VS Code, keeps a local history (the API only returns "now"), and — the part I think helps *you* most — **alerts when an editor update silently breaks the ad injection**, so users don't quietly stop earning.
>
> It only calls the read endpoints (`/v1/portfolio`, `/v1/earnings`) as the signed-in user — never metrics/billing. I built it to make Kickbacks more reliable and more *trusted* (the editor-patching makes some folks nervous), not to route around anything.
>
> Before I share it more widely, I wanted to give you a heads-up and ask: would you be open to it? Happy to make it official/blessed, add a "not affiliated" disclaimer, or adjust anything you're uncomfortable with.
>
> — Amit · [repo link]

Why it works: positions you as an ally who reduces their support burden and their 2.5★ trust problem — and it's the only clean path to ever commercializing (their license requires written permission).

### 14.3 Share on X — AFTER the heads-up

Reverse-engineering is the hook; the tool is the call-to-action:

> **1/** Kickbacks.ai pays you to show ads in your Claude Code & Codex "thinking…" spinner. I wanted to know what it does to my editor — so I read the code. Then I built an open-source companion for it. 🧵
>
> **2/** It patches the Claude Code & Codex extensions to paint an ad in the spinner. Good news for the paranoid (me): it's **read-only telemetry** — impressions/clicks only. It doesn't read your prompts or code. I checked.
>
> **3/** The catch: the earnings number only lives in VS Code's status bar, has no history, and **silently stops** when an editor update clobbers the patch. So I built a menu-bar app + CLI that shows earnings anywhere, keeps history, and **alerts you when it breaks**.
>
> **4/** Free + open source 👉 [repo]. Read-only by design — never fires a billing event. Gave @kickbacks a heads-up. ⭐ if it's useful.

### 14.4 To finalize

- **Handles needed:** GitHub username (FUNDING + repo link), Ko-fi / X handles.
- **Name:** lean neutral / non-affiliated (e.g., `kb` + a name like "Tally" / "Sidecar") so the post and email don't imply official status (§8, §13).
- **Don't auto-send:** all three are drafts for your own accounts and your timing.

---

## 15. UI / UX design (locked 2026-06-13)

Both surfaces render the same **model** — today, lifetime, rate ($/hr from local history), daily cap + reset, projected cap-hit, the served ad, status, and a 24h sparkline — but the **menu bar is glanceable** and the **CLI is rich**.

### 15.1 Menu bar (native Swift `MenuBarExtra`)

**Title (always visible): today's earnings + a trend arrow.**

```
$0.56 ▴   rising        $0.56 ▾   falling        $0.56 —   flat
```

- Trend arrow comes from the local-history rate over the last ~30 min.
- **Stall surfacing (watchdog USP, preserved despite the minimal title):** when *active but flat* (stalled), the flat `—` renders **amber** and a one-time macOS **notification** fires — *"Kicker: you're coding but not earning — the ad injection may have broken. Run 'Kickbacks: Restore'."* **Killed** → title dims; **signed out** → shows `kicker`.

**Dropdown (on click):**

```
  Kicker                         ● Earning
  ──────────────────────────────────────────
  Today          $0.56
  Lifetime       $12.34
  Rate           $0.18/hr  ▴
  Last 24h       ▁▂▃▅▇▆▄▃▂▄▅▇
  ──────────────────────────────────────────
  Daily cap      $0.56 / $1.00   (56%)
  Resets in      4h 12m
  Hits cap       ~2h 30m at this rate
  ──────────────────────────────────────────
  Now showing
   Inflowpay: Global sales, 50% less fees…  ↗   (opens click URL)
  ──────────────────────────────────────────
  ↻ Refresh now            Open dashboard ⌘D
  Sign out                       Quit Kicker
```

- The dropdown always carries the **explicit status line** (top-right dot) so the precise state is one click away. "Open dashboard" launches the CLI TUI.

### 15.2 CLI (OpenTUI — framed dashboard)

`kicker` renders a framed dashboard; `kicker watch` keeps it live (animated sparkline, pulsing status).

```
╭ kicker ──────────────────────────────────────  ● earning ╮
│   TODAY          LIFETIME          RATE                   │
│   $0.56          $12.34            $0.18/hr ▴             │
│                                                           │
│   Daily cap   ▰▰▰▰▰▰▰▰▱▱▱▱▱▱   $0.56 / $1.00 · resets 4h12m│
│   Projected   hits cap in ~2h 30m                         │
│                                                           │
│   24h   ▁▂▃▄▅▇▆▄▃▂▁▂▃▅▇█▆▄▃▂▃▅▇▆▄▂▁                       │
├ now showing ──────────────────────────────────────────────┤
│   ▣  Inflowpay: Global sales, 50% less fees…           ↗  │
│      campaign 23f8444b · ad 552e20ec                      │
╰─────────────────────────────────────────────  r refresh · q ╯
```

- Keys: `r` refresh · `h` history (wider chart) · `q` quit. `kicker watch` = live mode.
- Non-TTY / piped output falls back to plain text (the Plan 1 renderer) so it stays scriptable.

### 15.3 State matrix

| State | Menu title | Dropdown / TUI status | Extra |
|---|---|---|---|
| Earning | `$0.56 ▴/▾` | ● Earning (green) | — |
| Stalled | `$0.56 —` (amber) | ⚠ Stalled (amber) | one-time notification → "run Restore" |
| Cap reached | `$0.56 —` | ◐ Daily cap hit | "won't earn until reset" |
| Killed | `$0.56` (dim) | ⊘ Killswitch on | server kill flag |
| No-serve | `$0.00 —` | ○ No ad serving | "Your ad here" placeholder |
| Signed out | `kicker` | ○ Signed out | "run kicker login" |

This drives **Plan 2** (OpenTUI dashboard) and **Plan 4** (Swift menu).
