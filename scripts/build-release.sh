#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"; mkdir -p "$OUT"
echo "→ building CLI (bun)…"
( cd "$ROOT/cli" && bun install --frozen-lockfile && bun build ./src/cli.ts --compile --outfile "$OUT/kickback" )
echo "→ building menu-bar app (swift)…"
( cd "$ROOT/app" && swift build -c release && cp .build/release/KickbackBar "$OUT/kickback-bar" )
echo "✓ built: $OUT/kickback  $OUT/kickback-bar"
