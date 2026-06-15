# Security Policy

## Design posture

Kickbacks is **read-only**. It calls only:

- `GET /v1/portfolio`, `GET /v1/earnings` — your own account data
- the auth lifecycle: `/v1/auth/extension/{start,poll}`, `/v1/auth/refresh`, `/v1/auth/signout`

It **never** sends impression, billing, or metrics events. There is no `POST /v1/metrics`.

## Your data

- OAuth tokens are stored only on your machine at `~/.config/kickbacks/auth.json` (directory `0700`, file `0600`). Tokens are never logged or placed in URLs.
- `KICKBACKS_BASE` sends your bearer token to whatever host you set — only point it at infrastructure you trust.
- The CLI and the app communicate through a local SQLite store; nothing is sent to third parties.

## Reporting a vulnerability

Please open a private [GitHub security advisory](https://github.com/amitray007/kickbacks/security/advisories/new) rather than a public issue, with steps to reproduce. We'll respond as soon as we can.
