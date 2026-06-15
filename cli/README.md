# Kickbacks

Read-only CLI for your own Kickbacks.ai earnings. Not affiliated with Kickbacks.ai / ShiftKeys, Inc.

```bash
bun run src/cli.ts login        # Google sign-in (own session)
bun run src/cli.ts              # portfolio (default)
bun run src/cli.ts watch        # live dashboard — auto-refresh · r refresh · q quit
bun run src/cli.ts earnings
bun run src/cli.ts raw          # dump raw portfolio + earnings JSON (debug API drift)
bun run src/cli.ts status
bun run src/cli.ts logout       # revoke server-side session + clear local tokens
bun run src/cli.ts poll         # one poll cycle (sample + stall/cap alerts); the launchd agent runs this
```

Never sends billing events — only reads `/v1/portfolio` and `/v1/earnings`. The only writes are auth lifecycle (`/v1/auth/refresh`, `/v1/auth/signout`).

## Config

| Env | Default | Purpose |
|---|---|---|
| `KICKBACKS_BASE` | the backend Cloud Run URL | override the API base |
| `KICKBACKS_CC_VERSION` | `2.1.177` | `claude_code_version` sent with portfolio reads |
| `KICKBACKS_CONFIG_DIR` | `~/.config/kickbacks` | where `auth.json` + `history.db` live |
| `KICKBACKS_WATCH_SECONDS` | `30` | `watch` refresh interval (min 5) |
| `KICKBACKS_POLL_SECONDS` | `180` | background poller interval (launchd; min 30) |
| `KICKBACKS_ACTIVITY_DIRS` | `~/.claude/projects` | colon-separated dirs whose file mtimes mean "actively coding" (stall detection) |

Tokens are stored at `$KICKBACKS_CONFIG_DIR/auth.json` (chmod 600, in a 700 dir). Local history accumulates in `history.db`.

> ⚠️ **`KICKBACKS_BASE` sends your OAuth bearer token to whatever host you point it at.** Only set it to infrastructure you trust — never paste an unreviewed `KICKBACKS_BASE=…` from elsewhere. The login redirect is also required to be `https`.

## Background poller (Plan 3)

Sampling 24/7 — even with VS Code closed — turns the amnesiac backend into trend/rate history and powers the **stall watchdog** ("you're coding but earnings are flat — the ad injection may have broken") and **cap** alerts, delivered as macOS notifications. The installed `kickbacks` binary manages a launchd agent that runs `kickbacks poll` every few minutes:

```bash
kickbacks poller install     # write + load the launchd agent (~/Library/LaunchAgents)
kickbacks poller status
kickbacks poller uninstall
```

`poller install` must be run from the installed binary, not `bun run` (launchd needs the binary's own path). Stall detection treats you as "active" when a file under `KICKBACKS_ACTIVITY_DIRS` was modified recently — set that to your real Claude Code / Codex transcript dir(s) if the default is wrong. Notifications use `osascript` (macOS only).
