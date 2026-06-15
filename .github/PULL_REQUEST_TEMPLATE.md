## What & why

<!-- What does this change, and why? Link any related issue. -->

## Checklist

- [ ] `cd cli && bun test && bunx --bun tsc --noEmit` pass
- [ ] `cd app && swift build && swift test` pass (if the app changed)
- [ ] Stays **read-only** — no new write/metrics calls to the backend
- [ ] Updated README/docs if behavior changed
