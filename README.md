# Kicker

A reliable, open-source companion for [Kickbacks.ai](https://kickbacks.ai) — a **read-only** CLI + native macOS menu-bar app that shows your *own* earnings outside VS Code, keeps the local history the API doesn't, and warns you when the ad injection silently stops earning.

> **Not affiliated** with Kickbacks.ai or ShiftKeys, Inc. It reads only your own account data (`/v1/portfolio`, `/v1/earnings`) and **never** sends billing/impression events.

## Status — design & planning

This repo currently holds the design and the first build plan. Implementation is queued.

- **[docs/design.md](docs/design.md)** — full design: vision, the (reverse-engineered) read-only API surface, architecture, open-source / launch / earning strategy, risks, and the UI/UX for both surfaces.
- **[docs/plans/2026-06-13-kicker-core-cli.md](docs/plans/2026-06-13-kicker-core-cli.md)** — TDD plan for **Plan 1** (the core + CLI data layer both UIs read from).

## What it will be

- **CLI** (`kicker`) — TypeScript + OpenTUI framed dashboard; `kicker watch` for a live view.
- **Menu bar** — native Swift `MenuBarExtra`; today's earnings + trend always visible, dropdown with cap / rate / served ad, stall notifications.
- **Core** (TypeScript) — API client, Google-OAuth (its own session), SQLite history, poller + stall watchdog.
- **Distribution** — Homebrew tap (formula + cask).

## Principles

- **Read-only forever** — never `POST /v1/metrics`. An observatory, not a controller.
- **Standalone & reliable** — works with VS Code closed; the watchdog catches silent earning failures.
- **Open source, no subscription.**

## Roadmap

| Plan | Scope |
|---|---|
| 1 | Core + CLI MVP — auth, API client, SQLite history, text commands |
| 2 | OpenTUI dashboard |
| 3 | Poller + stall watchdog (launchd) |
| 4 | Native Swift menu-bar app |
| 5 | Homebrew tap (formula + cask) |

## Notes

- A working prototype (`kb.mjs`) that proved the API lives in the sibling `tries/reverse-engineer-kickbacks-ai/` exploration repo; it's ported into the core in Plan 1.
- Before any public release: email ShiftKeys/Andrew (design §14.2) and keep the "not affiliated" disclaimer.
