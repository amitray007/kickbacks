# Kickbacks

[![CI](https://github.com/amitray007/kickbacks/actions/workflows/ci.yml/badge.svg)](https://github.com/amitray007/kickbacks/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/amitray007/kickbacks?sort=semver)](https://github.com/amitray007/kickbacks/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

An unofficial, **read-only** companion for [Kickbacks.ai](https://kickbacks.ai) — a CLI and a native macOS menu-bar app that show *your own* earnings outside VS Code, keep the local history the API doesn't, and warn you when ad injection silently stops earning.

> **Not affiliated** with Kickbacks.ai or ShiftKeys, Inc. It reads only your own account data (`GET /v1/portfolio`, `GET /v1/earnings`) and **never** sends billing or impression events. Read-only, forever.

## Features

- **Menu-bar app** — today's earnings always in the menu bar (`K$ 12.34`); a rich dropdown with today/lifetime, your hourly/daily caps, recent ads, and inline history.
- **Live CLI** — `kickbacks` for a one-shot dashboard, `kickbacks watch` for a live TUI.
- **Local history** — samples into SQLite, so you get this-week/this-month, best day, averages, and pace projections the API doesn't keep.
- **Alerts** — native notifications when you hit a cap or cross a lifetime milestone, via a background launchd poller (works with VS Code closed).
- **Share cards** — generate a polished earnings image (Today / This week / Lifetime) to copy, save, or post.
- **Privacy & demo modes** — mask amounts for screen-sharing, or show believable sample numbers.
- **Floating HUD** — a pinnable, always-on-top mini window.

## Install (Homebrew)

```bash
brew tap amitray007/kickbacks https://github.com/amitray007/kickbacks
brew trust amitray007/kickbacks          # one-time: Homebrew gates third-party taps
brew install kickbacks                   # builds the CLI + menu-bar app from source (bun + swift)

kickbacks login                          # sign in with Google
kickbacks                                # earnings dashboard   ·   kickbacks watch  for live
kickbacks bar install                    # run the menu-bar app at login
kickbacks poller install                 # background sampling + cap / milestone alerts
```

Upgrade later with `brew update && brew upgrade kickbacks`. The [formula](Formula/kickbacks.rb) builds from source, so **no code-signing or notarization is required** — it compiles on your machine.

**Prefer a Mac app without Homebrew?** Clone the repo and run `scripts/install-app.sh` — it builds a self-contained `Kickbacks.app` (the CLI is bundled inside) and installs it to `/Applications`.

## Commands

| Command | What it does |
|---|---|
| `kickbacks` | One-shot earnings dashboard |
| `kickbacks watch` | Live TUI dashboard (`r` refresh · `q` quit) |
| `kickbacks earnings` | Earnings + cap detail |
| `kickbacks status` | Auth + config status |
| `kickbacks login` / `logout` | Google sign-in / sign-out |
| `kickbacks poller install\|uninstall\|status` | Background sampler + alerts (launchd) |
| `kickbacks bar install\|uninstall\|status` | Menu-bar app at login |

## How it works

Two tools, two languages, one shared local store:

- **`cli/`** — TypeScript on [Bun](https://bun.sh): the API client, its own Google-OAuth session, a `bun:sqlite` history store, all the earnings logic, and the poller/watchdog.
- **`app/`** — a Swift `MenuBarExtra` app. It holds no business logic; it shells out to `kickbacks model` / `kickbacks history` and renders the result — keeping a single source of truth in TypeScript.

The two are bridged by the local SQLite store, not by shared code. Full design notes live in [docs/](docs/).

## Configuration

All optional, via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `KICKBACKS_CONFIG_DIR` | `~/.config/kickbacks` | tokens + history database |
| `KICKBACKS_POLL_SECONDS` | `180` | background poller cadence (min 30) |
| `KICKBACKS_ACTIVITY_DIRS` | `~/.claude/projects` | "actively coding" heuristic source |
| `KICKBACKS_BASE` | Kickbacks backend | ⚠️ your OAuth bearer token is sent here — only point it at infrastructure you trust |

## Privacy & security

Read-only by design — it never `POST`s metrics or impression events. Your OAuth tokens live only in `~/.config/kickbacks/auth.json` on your own machine. See [SECURITY.md](SECURITY.md).

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for build/test setup and conventions.

## Building from source

```bash
# CLI (TypeScript / Bun)
cd cli && bun install && bun test && bun run build      # → dist/kickbacks

# Menu-bar app (Swift)
cd app && swift build && swift test
```

## License

[Apache-2.0](LICENSE). Not affiliated with Kickbacks.ai / ShiftKeys, Inc.
