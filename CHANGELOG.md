# Changelog

Notable changes per release. Loosely follows [Keep a Changelog](https://keepachangelog.com); versions are git tags.

## v0.1.0 — 2026-06-15

First public release.

- **CLI** (`kickbacks`) — earnings dashboard, `watch` live TUI, `earnings`/`status`, Google OAuth (read-only API client).
- **Menu-bar app** — today's earnings in the menu bar; dropdown with today/lifetime, hourly/daily caps, recent ads, and inline history; share cards (Today/Week/Lifetime); pinnable floating HUD; privacy + demo modes.
- **Local history** (SQLite) — this-week/this-month, best day, averages, pace projections.
- **launchd poller** — background sampling + cap and lifetime-milestone notifications.
- **Homebrew tap** — build-from-source formula (no code-signing/notarization required).
