#!/usr/bin/env bash
# Build the Kickback menu-bar app as a self-contained .app (the kickback CLI is bundled
# inside it) and install it to /Applications so it can be launched from Finder/Launchpad.
# Usage: scripts/install-app.sh [DEST_DIR]   (DEST_DIR defaults to /Applications)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-/Applications}"
APP="Kickback.app"
STAGE="$ROOT/dist/$APP"
MACOS="$STAGE/Contents/MacOS"

echo "-> building CLI (bun)..."
( cd "$ROOT/cli" && bun install --frozen-lockfile && bun build ./src/cli.ts --compile --outfile "$ROOT/dist/kickback" )
echo "-> building menu-bar app (swift)..."
( cd "$ROOT/app" && swift build -c release )

echo "-> assembling $APP ..."
rm -rf "$STAGE"
mkdir -p "$MACOS"
cp "$ROOT/app/.build/release/KickbackBar" "$MACOS/KickbackBar"
cp "$ROOT/dist/kickback" "$MACOS/kickback"   # bundled CLI -> app is self-contained
cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kickback</string>
  <key>CFBundleDisplayName</key><string>Kickback</string>
  <key>CFBundleIdentifier</key><string>ai.kickback.bar</string>
  <key>CFBundleExecutable</key><string>KickbackBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST

mkdir -p "$STAGE/Contents/Resources"
if [ -f "$ROOT/app/Resources/AppIcon.icns" ]; then
  cp "$ROOT/app/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
  echo "-> bundled app/Resources/AppIcon.icns"
else
  echo "-> no app/Resources/AppIcon.icns yet (using the default icon; drop one there to brand it)"
fi

echo "-> installing to $DEST/$APP ..."
mkdir -p "$DEST"
rm -rf "${DEST:?}/$APP"
cp -R "$STAGE" "$DEST/$APP"
echo "OK: installed $DEST/$APP"

# For a real /Applications install, kill the running menu-bar app and relaunch the
# fresh build (skipped for CI / temp-dir installs, which pass a custom DEST).
if [ "$DEST" = "/Applications" ]; then
  echo "-> relaunching Kickback ..."
  if pkill -x KickbackBar 2>/dev/null; then sleep 0.6; fi
  open "$DEST/$APP"
  echo "OK: Kickback relaunched"
else
  echo "    Launch from Launchpad/Finder, or:  open -a Kickback"
fi
echo "    (Branding: drop an AppIcon.icns into app/Resources/ and re-run to embed it.)"
