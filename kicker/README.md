# Kicker

Read-only CLI for your own Kickbacks.ai earnings. Not affiliated with Kickbacks.ai / ShiftKeys, Inc.

```bash
bun run src/cli.ts login        # Google sign-in (own session)
bun run src/cli.ts              # portfolio (default)
bun run src/cli.ts earnings
bun run src/cli.ts raw          # dump raw portfolio + earnings JSON (debug API drift)
bun run src/cli.ts status
bun run src/cli.ts logout       # revoke server-side session + clear local tokens
```

Never sends billing events — only reads `/v1/portfolio` and `/v1/earnings`. The only writes are auth lifecycle (`/v1/auth/refresh`, `/v1/auth/signout`).

## Config

| Env | Default | Purpose |
|---|---|---|
| `KICKER_BASE` | the backend Cloud Run URL | override the API base |
| `KICKER_CC_VERSION` | `2.1.177` | `claude_code_version` sent with portfolio reads |
| `KICKER_CONFIG_DIR` | `~/.config/kicker` | where `auth.json` + `history.db` live |

Tokens are stored at `$KICKER_CONFIG_DIR/auth.json` (chmod 600). Local history accumulates in `history.db`.
