#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"; mkdir -p "$OUT"
echo "→ building CLI (bun)…"
( cd "$ROOT/cli" && bun install --frozen-lockfile && bun build ./src/cli.ts --compile --outfile "$OUT/kickbacks" )
echo "→ building menu-bar app (swift)…"
( cd "$ROOT/app" && swift build -c release && cp .build/release/KickbacksBar "$OUT/kickbacks-bar" )
echo "✓ built: $OUT/kickbacks  $OUT/kickbacks-bar"
