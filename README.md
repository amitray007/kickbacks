# Kickback

A reliable, open-source companion for [Kickbacks.ai](https://kickbacks.ai) — a **read-only** CLI + native macOS menu-bar app that shows your *own* earnings outside VS Code, keeps the local history the API doesn't, and warns you when the ad injection silently stops earning.

> **Not affiliated** with Kickbacks.ai or ShiftKeys, Inc. It reads only your own account data (`/v1/portfolio`, `/v1/earnings`) and **never** sends billing/impression events.

## Status — Plans 1–4 shipped

The TypeScript core + CLI (**Plan 1**), the live OpenTUI `watch` dashboard (**Plan 2**), the launchd poller + stall/cap watchdog (**Plan 3**), and the native Swift `MenuBarExtra` app (**Plan 4**) are built and tested. Next: Homebrew packaging (Plan 5) — bundle the CLI binary + a signed `.app`.

- **[docs/design.md](docs/design.md)** — full design: vision, the (reverse-engineered) read-only API surface, architecture, strategy, risks, and the UI/UX for both surfaces.
- **[docs/plans/2026-06-13-kickback-core-cli.md](docs/plans/2026-06-13-kickback-core-cli.md)** — Plan 1 (core + CLI).
- **[docs/plans/2026-06-13-kickback-opentui-watch.md](docs/plans/2026-06-13-kickback-opentui-watch.md)** — Plan 2 (OpenTUI `watch`).
- **[docs/plans/2026-06-13-kickback-poller-watchdog.md](docs/plans/2026-06-13-kickback-poller-watchdog.md)** — Plan 3 (poller + watchdog).
- **[docs/plans/2026-06-13-kickback-menubar-app.md](docs/plans/2026-06-13-kickback-menubar-app.md)** — Plan 4 (Swift menu-bar app).

## What it will be

- **CLI** (`kickback`) — TypeScript + OpenTUI framed dashboard; `kickback watch` for a live view.
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
  cli/        ← the `kickback` CLI (TypeScript/Bun) — also hosts the shared core + poller
  app/        ← the menu-bar app (Swift `MenuBarExtra`) — renders `kickback model`
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
| 5 | Homebrew tap (formula + cask) |

## Notes

- A working prototype (`kb.mjs`) that proved the API lives in the sibling `tries/reverse-engineer-kickbacks-ai/` exploration repo; it's ported into the core in Plan 1.
- Before any public release: email ShiftKeys/Andrew (design §14.2) and keep the "not affiliated" disclaimer.
