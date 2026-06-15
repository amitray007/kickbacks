# Kickbacks menu-bar app

Native macOS `MenuBarExtra` app — a **thin renderer** of `kickbacks model` / `kickbacks history`.
The menu-bar title shows today's earnings (`K$ 12.34`, state-tinted); the dropdown shows
today/lifetime, your hourly/daily caps, recent ads, and inline history — plus share cards, a
pinnable floating HUD, and privacy/demo modes.

All earnings logic lives in the `kickbacks` CLI; this app just spawns it and renders the JSON.
Menu-bar-only (no Dock icon). Not affiliated with Kickbacks.ai / ShiftKeys, Inc.

## Build & run

```bash
cd app
swift build                  # debug · or: swift build -c release → .build/release/KickbacksBar
swift test                   # KickbacksKit unit tests (headless)
swift run KickbacksBar       # launches the menu-bar item (GUI)
```

The app finds the CLI via `$KICKBACKS_BIN`, then a sibling binary (when bundled inside
`Kickbacks.app`), then `/opt/homebrew/bin/kickbacks` / `/usr/local/bin/kickbacks`. For
development, build the CLI and point at it:

```bash
(cd ../cli && bun run build)                        # → ../cli/dist/kickbacks
KICKBACKS_BIN="$PWD/../cli/dist/kickbacks" swift run KickbacksBar
```

The panel refreshes on open and on **Refresh**. `scripts/install-app.sh` assembles a
self-contained `Kickbacks.app` (CLI bundled inside) — build-from-source, no signing required.
