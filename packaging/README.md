# Packaging — Homebrew tap

Kickbacks ships as a **single-repo Homebrew tap** that builds from source (bun + swift) — no
signing/notarization needed (locally-compiled binaries aren't quarantined). The formula lives
at [`Formula/kickbacks.rb`](../Formula/kickbacks.rb) in this repo.

## Install

```bash
brew tap amitray007/kickbacks https://github.com/amitray007/kickbacks
brew trust amitray007/kickbacks      # one-time: Homebrew gates third-party taps
brew install kickbacks
```

`brew install --HEAD kickbacks` builds straight from `main` before a release. Local dry-run
without brew: `scripts/build-release.sh` → `dist/kickbacks`, `dist/kickbacks-bar`.

## Cut a release (maintainers)

Bump `cli/package.json`, then tag:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

`.github/workflows/release.yml` builds the macOS artifacts and **auto-bumps** the formula's
`url` + `sha256` to the new tag, so `brew upgrade kickbacks` tracks releases — no manual
formula editing.
