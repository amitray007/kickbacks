# Kickbacks menu-bar app

Native macOS `MenuBarExtra` app — a **thin renderer** of `kickbacks model --json`. The
menu-bar title shows today's earnings + a trend arrow; the dropdown shows lifetime, rate,
the daily cap + reset + projection, a 24h sparkline, the served ad, and a status line.

All earnings logic lives in the `kickbacks` CLI; this app just spawns it and renders the
JSON. Menu-bar-only (no Dock icon). Not affiliated with Kickbacks.ai / ShiftKeys, Inc.

## Build & run

```bash
cd app
swift build                 # debug · or: swift build -c release → .build/release/KickbacksBar
swift test                  # KickbacksKit model-decode tests (headless)
swift run KickbacksBar       # launches the menu-bar item (GUI)
```

The app finds the CLI via `$KICKBACKS_BIN`, then `/opt/homebrew/bin/kickbacks`,
`/usr/local/bin/kickbacks`. For development, build the CLI binary and point at it:

```bash
(cd ../cli && bun run build)                       # → ../cli/dist/kickbacks
KICKBACKS_BIN="$PWD/../cli/dist/kickbacks" swift run KickbacksBar
```

The dropdown refreshes every 60s and on **Refresh**. Plan 5 bundles this into a signed
`.app` + a Homebrew cask.
