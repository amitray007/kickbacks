# Contributing

Thanks for your interest! Kickbacks is a small, **read-only** companion for Kickbacks.ai. Bug reports, fixes, and features are all welcome.

## Ground rules

- **Read-only, forever.** The tool must never write to the backend except the auth lifecycle (login / token refresh / sign-out). It must never `POST` impression, billing, or metrics events. PRs that break this won't be merged.
- **Not affiliated** with Kickbacks.ai / ShiftKeys, Inc. Keep the disclaimer intact and don't reproduce their logo/brand artwork.

## Project layout

- `cli/` — TypeScript (Bun): API client, OAuth, SQLite history, earnings logic, poller. The single source of truth.
- `app/` — Swift `MenuBarExtra` app; renders `kickbacks model` / `kickbacks history`. No business logic.
- `Formula/` — Homebrew formula · `scripts/` — build/install · `docs/` — design + plans.

## Dev setup

```bash
# CLI (TypeScript / Bun)
cd cli
bun install
bun test                  # tests
bunx --bun tsc --noEmit   # typecheck
bun run start -- status   # run a command locally

# Menu-bar app (Swift)
cd app
swift build
swift test
```

`scripts/install-app.sh` builds + installs a self-contained `Kickbacks.app` to `/Applications` for end-to-end testing.

## Conventions

- TypeScript is strict; keep logic pure and unit-tested (the CLI does the work, Swift only renders).
- Swift: `swift test` covers the `KickbacksKit` library; the UI is manual QA.
- Commit messages: conventional-ish (`feat:`, `fix:`, `chore:`, `docs:`), present tense.
- Keep both suites green — CI runs `bun test` + `swift test` on every push and PR.

## Releasing (maintainers)

Bump `cli/package.json`, then:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

CI builds the release artifacts **and** auto-bumps `Formula/kickbacks.rb`, so `brew upgrade kickbacks` tracks the new version.
