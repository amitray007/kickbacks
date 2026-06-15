# Packaging — Homebrew tap

Kickbacks ships via a Homebrew **tap** that builds from source (bun + swift) — no
signing/notarization needed (locally-compiled binaries aren't quarantined).

## One-time: create the tap

1. Create a public repo named **`homebrew-tap`** under your GitHub account
   (e.g. `github.com/USER/homebrew-tap`).
2. Copy `kickbacks.rb` into it (tap formulae live at the repo root or in `Formula/`).
3. In `kickbacks.rb`, set `homepage`/`url`/`head` to your repo.

## Cut a release

```bash
git tag v0.1.0 && git push --tags          # in the kickbacks repo
URL="https://github.com/USER/kickbacks/archive/refs/tags/v0.1.0.tar.gz"
curl -sL "$URL" | shasum -a 256            # paste into kickbacks.rb `sha256`
```

## Install

```bash
brew install USER/tap/kickbacks             # builds CLI + menu-bar from source
brew install --HEAD USER/tap/kickbacks      # or straight from main, before a release
```

Then: `kickbacks login` · `kickbacks poller install` · `kickbacks bar install`.

Local dry-run of the build (no brew): `scripts/build-release.sh` → `dist/kickbacks`, `dist/kickbacks-bar`.
