# Kickbacks

A reliable, open-source companion for [Kickbacks.ai](https://kickbacks.ai) — a **read-only** CLI + native macOS menu-bar app that shows your *own* earnings outside VS Code, keeps the local history the API doesn't, and warns you when the ad injection silently stops earning.

> **Not affiliated** with Kickbacks.ai or ShiftKeys, Inc. It reads only your own account data (`/v1/portfolio`, `/v1/earnings`) and **never** sends billing/impression events.

## Status — Plans 1–5 shipped

The TypeScript core + CLI (**Plan 1**), the live OpenTUI `watch` dashboard (**Plan 2**), the launchd poller + stall/cap watchdog (**Plan 3**), the native Swift `MenuBarExtra` app (**Plan 4**), and the Homebrew tap (**Plan 5**) are built and tested. Distribution is build-from-source (no signing/notarization): the formula compiles the CLI binary and the menu-bar app on the user's machine.

- **[docs/design.md](docs/design.md)** — full design: vision, the (reverse-engineered) read-only API surface, architecture, strategy, risks, and the UI/UX for both surfaces.
- **[docs/plans/2026-06-13-kickbacks-core-cli.md](docs/plans/2026-06-13-kickbacks-core-cli.md)** — Plan 1 (core + CLI).
- **[docs/plans/2026-06-13-kickbacks-opentui-watch.md](docs/plans/2026-06-13-kickbacks-opentui-watch.md)** — Plan 2 (OpenTUI `watch`).
- **[docs/plans/2026-06-13-kickbacks-poller-watchdog.md](docs/plans/2026-06-13-kickbacks-poller-watchdog.md)** — Plan 3 (poller + watchdog).
- **[docs/plans/2026-06-13-kickbacks-menubar-app.md](docs/plans/2026-06-13-kickbacks-menubar-app.md)** — Plan 4 (Swift menu-bar app).
- **[docs/plans/2026-06-13-kickbacks-homebrew-tap.md](docs/plans/2026-06-13-kickbacks-homebrew-tap.md)** — Plan 5 (Homebrew tap).

## Install (Homebrew)

```bash
brew tap amitray007/kickbacks https://github.com/amitray007/kickbacks
brew install kickbacks              # builds the CLI + menu-bar app from source (bun + swift)
kickbacks login                     # Google sign-in
kickbacks                           # earnings dashboard  ·  kickbacks watch  for the live view
kickbacks poller install            # background sampling + stall/cap alerts (launchd)
kickbacks bar install               # menu-bar app at login

brew update && brew upgrade kickbacks   # later: pull the newest release
```

Build-from-source means no code-signing/notarization is required (it compiles on your machine). The [formula](Formula/kickbacks.rb) auto-tracks each `v*` tag (see `.github/workflows/release.yml`), so `brew upgrade` always gets the latest. Not affiliated with Kickbacks.ai / ShiftKeys, Inc.

**Prefer a Mac app (no brew)?** Run `scripts/install-app.sh` — it builds a self-contained `Kickbacks.app` (the `kickbacks` CLI is bundled inside) and installs it to `/Applications`; launch it from Launchpad. `scripts/build-release.sh` just builds the raw `dist/` binaries.

## What it will be

- **CLI** (`kickbacks`) — TypeScript + OpenTUI framed dashboard; `kickbacks watch` for a live view.
- **Menu bar** — native Swift `MenuBarExtra`; today's earnings + trend always visible, dropdown with cap / rate / served ad, stall notifications.
- **Core** (TypeScript) — API client, Google-OAuth (its own session), SQLite history, poller + stall watchdog.
- **Distribution** — Homebrew tap (formula + cask).

## Principles

- **Read-only forever** — never `POST /v1/metrics`. An observatory, not a controller.
- **Standalone & reliable** — works with VS Code closed; the watchdog catches silent earning failures.
- **Open source, no subscription.**

## Layout

```
kickbacks/    ← this repo (umbrella)
  docs/       ← design + plans
  cli/        ← the `kickbacks` CLI (TypeScript/Bun) — also hosts the shared core + poller
  app/        ← the menu-bar app (Swift `MenuBarExtra`) — renders `kickbacks model`
  packaging/  ← Homebrew tap (formula + cask)          · Plan 5
```

Two tools, two languages — bridged by a shared local SQLite store, not shared code.

## Roadmap

| Plan | Scope |
|---|---|
| 1 ✅ | Core + CLI MVP — auth, API client, SQLite history, text commands |
| 2 ✅ | OpenTUI `watch` dashboard |
| 3 ✅ | Poller + stall watchdog (launchd) |
| 4 ✅ | Native Swift menu-bar app |
| 5 ✅ | Homebrew tap (build-from-source formula) |

## Notes

- A working prototype (`kb.mjs`) that proved the API lives in the sibling `tries/reverse-engineer-kickbacks-ai/` exploration repo; it's ported into the core in Plan 1.
- Before any public release: email ShiftKeys/Andrew (design §14.2) and keep the "not affiliated" disclaimer.
