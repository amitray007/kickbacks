# Kickback

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
| `KICKBACK_BASE` | the backend Cloud Run URL | override the API base |
| `KICKBACK_CC_VERSION` | `2.1.177` | `claude_code_version` sent with portfolio reads |
| `KICKBACK_CONFIG_DIR` | `~/.config/kickback` | where `auth.json` + `history.db` live |

Tokens are stored at `$KICKBACK_CONFIG_DIR/auth.json` (chmod 600, in a 700 dir). Local history accumulates in `history.db`.

> ⚠️ **`KICKBACK_BASE` sends your OAuth bearer token to whatever host you point it at.** Only set it to infrastructure you trust — never paste an unreviewed `KICKBACK_BASE=…` from elsewhere. The login redirect is also required to be `https`.
