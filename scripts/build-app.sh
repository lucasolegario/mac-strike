#!/usr/bin/env bash
# build-app.sh — builds MacStrike.app, signs, notarizes and packages a DMG.
#
# Works with only the Command Line Tools (no full Xcode): it builds the SwiftPM
# release binary and assembles the .app bundle by hand.
#
# Signing + notarization need an Apple Developer account ($99/yr) and a
# "Developer ID Application" certificate installed in your keychain. Configure
# via environment variables (all optional — without them you get an unsigned app
# for local testing):
#
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE  a notarytool keychain profile (recommended), created once with:
#                     xcrun notarytool store-credentials MacStrikeNotary \
#                       --apple-id you@email.com --team-id TEAMID --password <app-specific-pw>
#   (or) APPLE_ID + TEAM_ID + APP_PASSWORD   instead of NOTARY_PROFILE
#
# Usage:
#   bash scripts/build-app.sh            # build + sign + notarize + DMG (as configured)
#   bash scripts/build-app.sh --no-dmg   # skip the DMG, just the .app
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="MacStrike"
EXECUTABLE="macstrike-gui"
BUNDLE_ID="com.macstrike.app"
VERSION="$(/usr/bin/grep -m1 MARKETING_VERSION project.yml 2>/dev/null | sed 's/[^0-9.]//g')"
VERSION="${VERSION:-0.1.0}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
MAKE_DMG=1
[ "${1:-}" = "--no-dmg" ] && MAKE_DMG=0

echo "==> Building release binary"
swift build -c release --product "$EXECUTABLE"
BIN="$(swift build -c release --product "$EXECUTABLE" --show-bin-path)/$EXECUTABLE"
[ -x "$BIN" ] || { echo "build failed: $BIN not found" >&2; exit 1; }

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Info.plist (based on GUISupport/Info.plist, with the executable name fixed).
/usr/libexec/PlistBuddy -c "Print" GUISupport/Info.plist >/dev/null 2>&1 \
  && cp GUISupport/Info.plist "$APP/Contents/Info.plist" \
  || cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true

echo "==> Generating app icon"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$DIST/icon-1024.png" >/dev/null
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s "$DIST/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
done
# Retina (@2x) variants Apple expects
cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"   2>/dev/null || true
cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"   2>/dev/null || true
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png" 2>/dev/null || true
rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
  && echo "    icon OK" || echo "    icon skipped"

# ---------------------------------------------------------------------------
# Signing
# ---------------------------------------------------------------------------
if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> Signing with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ROOT/GUISupport/$APP_NAME.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> No SIGN_IDENTITY set — ad-hoc signing (local use only, not distributable)"
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# DMG
# ---------------------------------------------------------------------------
DMG="$DIST/$APP_NAME-$VERSION.dmg"
if [ "$MAKE_DMG" = 1 ]; then
  echo "==> Creating DMG"
  STAGE="$DIST/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  [ -n "${SIGN_IDENTITY:-}" ] && codesign --force --sign "$SIGN_IDENTITY" "$DMG" || true
fi

# ---------------------------------------------------------------------------
# Notarization
# ---------------------------------------------------------------------------
notarize() {
  local target="$1"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$target" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
      --password "$APP_PASSWORD" --wait
  else
    return 2
  fi
}

if [ -n "${SIGN_IDENTITY:-}" ]; then
  TARGET="$DMG"; [ "$MAKE_DMG" = 1 ] || TARGET="$APP"
  echo "==> Notarizing $TARGET"
  if notarize "$TARGET"; then
    echo "==> Stapling"
    xcrun stapler staple "$TARGET" || true
    [ "$MAKE_DMG" = 1 ] && xcrun stapler staple "$APP" || true
    echo "DONE: notarized + stapled."
  else
    echo "    No notarization credentials set (NOTARY_PROFILE or APPLE_ID/TEAM_ID/APP_PASSWORD)."
    echo "    App is signed but NOT notarized — Gatekeeper will still warn on download."
  fi
else
  echo "==> Skipping notarization (unsigned build)."
fi

echo
echo "Artifacts in: $DIST"
ls -la "$DIST" | grep -E "\.app|\.dmg" || true
