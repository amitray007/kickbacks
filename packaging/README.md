# Packaging — Homebrew tap

Kickback ships via a Homebrew **tap** that builds from source (bun + swift) — no
signing/notarization needed (locally-compiled binaries aren't quarantined).

## One-time: create the tap

1. Create a public repo named **`homebrew-tap`** under your GitHub account
   (e.g. `github.com/USER/homebrew-tap`).
2. Copy `kickback.rb` into it (tap formulae live at the repo root or in `Formula/`).
3. In `kickback.rb`, set `homepage`/`url`/`head` to your repo.

## Cut a release

```bash
git tag v0.1.0 && git push --tags          # in the kickbacks repo
URL="https://github.com/USER/kickbacks/archive/refs/tags/v0.1.0.tar.gz"
curl -sL "$URL" | shasum -a 256            # paste into kickback.rb `sha256`
```

## Install

```bash
brew install USER/tap/kickback             # builds CLI + menu-bar from source
brew install --HEAD USER/tap/kickback      # or straight from main, before a release
```

Then: `kickback login` · `kickback poller install` · `kickback bar install`.

Local dry-run of the build (no brew): `scripts/build-release.sh` → `dist/kickback`, `dist/kickback-bar`.
