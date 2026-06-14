# Kickback — Plan 5: Homebrew tap (build-from-source)

> **For agentic workers:** TS in `cli/`, packaging in `packaging/` + root. Commit per task on `main`. The actual `brew install` / tap-publish are the user's (their GitHub + Homebrew); everything else is built/verified here.

**Goal:** Ship `kickback` (CLI) + `kickback-bar` (menu-bar app) via a Homebrew **tap formula** that **builds from source** (bun + swift) — so there's **no code-signing, no notarization, no Gatekeeper quarantine** (locally-compiled binaries aren't quarantined). `brew install <user>/tap/kickback` → both binaries on PATH; `kickback bar install` sets up the menu-bar app to launch at login.

**Decisions (locked 2026-06-13):**
- **License: Apache-2.0** (design §8/§13.3 — resolves the open item).
- **Build-from-source formula** (no bottles, no cask, no signing). Verified: `bun build --compile` (66 MB) + `swift build -c release` (205 KB) both build + run here.
- **Menu-bar app = `kickback-bar` binary** (no `.app` bundle); auto-start via a GUI LaunchAgent (`kickback bar install`), symmetric with the poller. Manual Login Items documented as the alternative.

**Hand-off (user-only):** create the GitHub tap repo, tag a release (fill the formula `url`+`sha256`), run `brew install`, and the live GUI/login checks. I provide the formula, build script, LICENSE, the `bar` command, and docs.

---

## File Structure

```
LICENSE                         # NEW — Apache-2.0
cli/package.json                # + "license": "Apache-2.0"
cli/src/config.ts               # + BAR_LAUNCHD_LABEL
cli/src/launchd.ts              # + guiPlistContent + installBarAgent (reuse load/uninstall)
cli/src/cli.ts                  # + `bar install|uninstall|status`
cli/test/launchd.test.ts        # + guiPlistContent test
packaging/kickback.rb           # NEW — the Homebrew formula (build-from-source)
packaging/README.md             # NEW — tap setup + release steps
scripts/build-release.sh        # NEW — build both binaries into dist/ (CI / local)
README.md                       # + Install (Homebrew) section
```

---

## Task 1 — LICENSE + license metadata

**Files:** `LICENSE`, `cli/package.json`.

- [ ] **Step 1:** add `LICENSE` with the standard **Apache License 2.0** text (copyright line: `Copyright 2026 <project authors>`).
- [ ] **Step 2:** set `"license": "Apache-2.0"` in `cli/package.json`.
- [ ] **Step 3:** commit `chore: add Apache-2.0 LICENSE`.

---

## Task 2 — GUI LaunchAgent + `kickback bar`

**Files:** `cli/src/config.ts`, `cli/src/launchd.ts`, `cli/src/cli.ts`, `cli/test/launchd.test.ts`.

- [ ] **Step 1: failing test** (`launchd.test.ts`) — a GUI (Aqua, KeepAlive) plist for the menu-bar binary:
```ts
import { guiPlistContent } from "../src/launchd";
test("guiPlistContent runs the binary at login in the Aqua session", () => {
  const xml = guiPlistContent("ai.kickback.bar", "/opt/homebrew/bin/kickback-bar");
  expect(xml).toContain("<string>ai.kickback.bar</string>");
  expect(xml).toContain("<string>/opt/homebrew/bin/kickback-bar</string>");
  expect(xml).toContain("<key>RunAtLoad</key><true/>");
  expect(xml).toContain("Aqua"); // LimitLoadToSessionType
  expect(xml).not.toContain("StartInterval"); // long-running, not interval
});
```
- [ ] **Step 2:** `launchd.ts` — add (reusing the existing escape + an extracted loader):
```ts
export function guiPlistContent(label: string, binPath: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${xmlEscape(label)}</string>
  <key>ProgramArguments</key><array><string>${xmlEscape(binPath)}</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
`;
}
export function installBarAgent(label: string, binPath: string): string {
  const path = plistPath(label);
  mkdirSync(join(homedir(), "Library/LaunchAgents"), { recursive: true });
  writeFileSync(path, guiPlistContent(label, binPath));
  spawnSync("launchctl", ["unload", path], { stdio: "ignore" });
  const r = spawnSync("launchctl", ["load", path], { stdio: "pipe", encoding: "utf8" });
  if (r.status !== 0) throw new Error(`launchctl load failed: ${(r.stderr || "").trim() || "unknown error"}`);
  return path;
}
```
(`uninstallAgent` / `agentInstalled` already work by label.)
- [ ] **Step 3:** `config.ts` — `export const BAR_LAUNCHD_LABEL = "ai.kickback.bar";`
- [ ] **Step 4:** `cli.ts` — `bar` command; resolve the sibling binary (`kickback-bar` next to `kickback`):
```ts
async function cmdBar() {
  const sub = (process.argv[3] || "status").toLowerCase();
  if (sub === "install") {
    if (process.argv[1]?.endsWith(".ts")) { console.error("`bar install` needs the installed binaries (brew), not `bun run`."); process.exit(1); }
    const barBin = join(dirname(process.execPath), "kickback-bar");
    if (!existsSync(barBin)) { console.error(`kickback-bar not found at ${barBin} (install via brew).`); process.exit(1); }
    const path = installBarAgent(BAR_LAUNCHD_LABEL, barBin);
    console.log(`Installed menu-bar agent → ${path}\nThe menu bar starts at login. Uninstall: kickback bar uninstall`);
  } else if (sub === "uninstall") { uninstallAgent(BAR_LAUNCHD_LABEL); console.log("Menu-bar agent uninstalled."); }
  else { console.log(`Menu-bar agent ${agentInstalled(BAR_LAUNCHD_LABEL) ? "installed" : "not installed"}  (${BAR_LAUNCHD_LABEL})`); }
}
```
Add `dirname`, `existsSync` imports; import `installBarAgent`, `BAR_LAUNCHD_LABEL`; register `bar` in the table + usage.
- [ ] **Step 5:** `bun test` + `tsc` green; `bun run src/cli.ts bar status` → "not installed". Commit `feat(bar): launch the menu-bar app at login via a GUI LaunchAgent`.

---

## Task 3 — Release build script

**Files:** `scripts/build-release.sh`.

- [ ] **Step 1:** a script that builds both binaries into `dist/` (for local install / a GitHub release):
```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"; mkdir -p "$OUT"
echo "→ building CLI (bun)…"
( cd "$ROOT/cli" && bun install --frozen-lockfile && bun build ./src/cli.ts --compile --outfile "$OUT/kickback" )
echo "→ building menu-bar app (swift)…"
( cd "$ROOT/app" && swift build -c release && cp .build/release/KickbackBar "$OUT/kickback-bar" )
echo "✓ built: $OUT/kickback  $OUT/kickback-bar"
```
- [ ] **Step 2:** `chmod +x scripts/build-release.sh`; run it → both binaries in `dist/`; `dist/kickback status` works. (`dist/` is gitignored.)
- [ ] **Step 3:** commit `chore: add build-release.sh (CLI + menu-bar binaries)`.

---

## Task 4 — Homebrew formula

**Files:** `packaging/kickback.rb`.

- [ ] **Step 1:** build-from-source formula (placeholders for the release `url`/`sha256`; `head` for testing-from-source):
```ruby
class Kickback < Formula
  desc "Read-only CLI + menu-bar app for your own Kickbacks.ai earnings (unofficial)"
  homepage "https://github.com/USER/kickbacks"
  url "https://github.com/USER/kickbacks/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_ON_RELEASE"
  license "Apache-2.0"
  head "https://github.com/USER/kickbacks.git", branch: "main"

  depends_on "bun" => :build
  depends_on :macos
  depends_on xcode: :build

  def install
    cd "cli" do
      system "bun", "install", "--frozen-lockfile"
      system "bun", "build", "./src/cli.ts", "--compile", "--outfile", "kickback"
      bin.install "kickback"
    end
    cd "app" do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/KickbackBar" => "kickback-bar"
    end
  end

  def caveats
    <<~EOS
      Read-only companion for Kickbacks.ai — not affiliated with Kickbacks.ai / ShiftKeys, Inc.

      Get started:
        kickback login
        kickback                 # earnings dashboard
        kickback poller install  # background sampling + stall/cap alerts (launchd)
        kickback bar install     # menu-bar app at login
    EOS
  end

  test do
    assert_match "kickback status", shell_output("#{bin}/kickback status 2>&1")
    assert_path_exists bin/"kickback-bar"
  end
end
```
- [ ] **Step 2:** `brew style packaging/kickback.rb` and `brew audit --formula packaging/kickback.rb` → clean (fix lint). **Do not** `brew install` here (that's the user's, and needs the published tarball). 
- [ ] **Step 3:** commit `feat(packaging): Homebrew formula (build-from-source: CLI + menu-bar)`.

---

## Task 5 — Docs + memory

**Files:** `packaging/README.md`, `README.md`, `docs/design.md`, memory.

- [ ] **Step 1:** `packaging/README.md` — tap setup + release: create `homebrew-tap` repo, copy `kickback.rb`, tag a release, fill `url`/`sha256` (`brew fetch`/`shasum -a 256`), test with `brew install --HEAD USER/tap/kickback`, then `brew install USER/tap/kickback`.
- [ ] **Step 2:** `README.md` — an **Install (Homebrew)** section (`brew install USER/tap/kickback`, then `kickback login` / `poller install` / `bar install`).
- [ ] **Step 3:** `docs/design.md` §13.3 → license RESOLVED (Apache-2.0); mark Plan 5 in the roadmap.
- [ ] **Step 4:** update memory (Plans 1–5 shipped).
- [ ] **Step 5:** commit `docs: Homebrew install + tap setup; license resolved (Apache-2.0)`.

---

## Self-Review

**Spec coverage (design §8 distribution):** Homebrew tap formula ✅ (Task 4); CLI + menu-bar both installed ✅; no subscription/paid ✅; license Apache-2.0 ✅ (Task 1). Cask + signing/notarization **intentionally dropped** (user decision: brew-only, unsigned → build-from-source avoids quarantine).
**Verifiable here:** LICENSE, `bar` command (+ test), build script (runs), `brew style`/`audit` on the formula. **User-only:** publishing the tap repo, tagging the release (url/sha256), `brew install`, live GUI/login QA.
**Reuse:** `bar` reuses the launchd escape/load helpers; no new packaging logic duplicated.
