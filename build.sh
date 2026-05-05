#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Load notarization credentials from .env if present
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

CONFIG="release"
APP_NAME="Awake"
BUNDLE_ID="com.diabdiab.awake"
VERSION="0.1"
BUILD_NUMBER="${BUILD_NUMBER:-3}"

echo "▸ swift build -c $CONFIG (universal: arm64 + x86_64)"
swift build -c "$CONFIG" --arch arm64 --arch x86_64

# Universal builds land in apple/Products/Release/, single-arch in <arch>-apple-macosx/$CONFIG.
BIN=".build/apple/Products/Release/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  BIN=".build/$CONFIG/$APP_NAME"
fi
if [[ ! -x "$BIN" ]]; then
  echo "Build did not produce $APP_NAME binary" >&2
  exit 1
fi

OUT="build/$APP_NAME.app"
rm -rf "build"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

cp "$BIN" "$OUT/Contents/MacOS/$APP_NAME"

if [[ -f "icon/AppIcon.icns" ]]; then
  cp "icon/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
fi

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Awake.</string>
  <key>NSAppleEventsUsageDescription</key><string>Awake uses AppleScript to ask for admin rights so it can keep your Mac awake with the lid closed.</string>
</dict>
</plist>
PLIST

# Developer ID signing for distribution outside the Mac App Store. Set
# SIGNING_IDENTITY (and TEAM_ID for notarization) in .env or the environment.
# Falls back to ad-hoc signing if neither is set or the identity isn't in the
# keychain — fine for local-only builds.
IDENTITY="${SIGNING_IDENTITY:-}"
TEAM_ID="${TEAM_ID:-}"

if [[ -n "$IDENTITY" ]] && security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "▸ Signing with Developer ID…"
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$OUT"
  SIGNED_FOR_DISTRIBUTION=1
else
  echo "▸ No Developer ID found — ad-hoc signing for local use"
  codesign --force --deep --sign - "$OUT"
  SIGNED_FOR_DISTRIBUTION=0
fi

echo "✓ Built & signed $OUT"

# Notarization (requires APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD env vars and a
# real Developer ID signature). Skips silently if the password is the placeholder
# from the .env template.
PLACEHOLDER="YOUR_APP_SPECIFIC_PASSWORD_HERE"
if [[ "$SIGNED_FOR_DISTRIBUTION" == "1" \
      && -n "${APPLE_ID:-}" \
      && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" \
      && -n "${TEAM_ID:-}" \
      && "${APPLE_APP_SPECIFIC_PASSWORD}" != "$PLACEHOLDER" ]]; then
  ZIP="build/${APP_NAME}-${VERSION}.zip"
  ditto -c -k --keepParent "$OUT" "$ZIP"

  echo "▸ Notarizing ${ZIP}"
  xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

  echo "▸ Stapling ticket to ${OUT}"
  xcrun stapler staple "$OUT"

  # Re-zip after stapling so the released archive carries the ticket.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$OUT" "$ZIP"

  echo "✓ Notarized & stapled"
  echo "  Release zip: ${ZIP}"
else
  echo "  Skipping notarization (set APPLE_ID and APPLE_APP_SPECIFIC_PASSWORD to enable)"
fi

echo "  Open with:  open $OUT"
echo "  Or move to /Applications and launch from there."
