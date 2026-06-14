#!/usr/bin/env bash
# Regenerate the Kickback app icon: app/Resources/AppIcon.svg + AppIcon.icns
# from the parametric source in scripts/gen-icon.ts.
# Needs: bun (pulls @resvg/resvg-js into a temp dir) + iconutil (macOS built-in).
# Usage: scripts/gen-icon.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/app/Resources"
mkdir -p "$RES"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "-> rasterizing (resvg) ..."
cp "$ROOT/scripts/gen-icon.ts" "$TMP/gen-icon.ts"
( cd "$TMP" && bun add @resvg/resvg-js >/dev/null 2>&1 && bun run gen-icon.ts "$RES" "$TMP/AppIcon.iconset" )

echo "-> assembling AppIcon.icns (iconutil) ..."
iconutil -c icns "$TMP/AppIcon.iconset" -o "$RES/AppIcon.icns"

echo "OK: $RES/AppIcon.svg + $RES/AppIcon.icns"
echo "    Embed it:  scripts/install-app.sh   (copies AppIcon.icns into Kickback.app)"
