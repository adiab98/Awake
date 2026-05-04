#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
APP_NAME="Awake"
BUNDLE_ID="${BUNDLE_ID:-com.diabdiab.awake}"
VERSION="${VERSION:-0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
ENTITLEMENTS="Awake-AppStore.entitlements"
OUT_DIR="build/AppStore"
APP_PATH="$OUT_DIR/$APP_NAME.app"
PKG_PATH="$OUT_DIR/$APP_NAME-$VERSION-$BUILD_NUMBER-mas.pkg"

echo "> swift build -c $CONFIG (Mac App Store variant)"
swift build --disable-sandbox -c "$CONFIG" --arch arm64 --arch x86_64 -Xswiftc -DAPP_STORE

BIN=".build/apple/Products/Release/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  BIN=".build/$CONFIG/$APP_NAME"
fi
if [[ ! -x "$BIN" ]]; then
  echo "Build did not produce $APP_NAME binary" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BIN" "$APP_PATH/Contents/MacOS/$APP_NAME"

if [[ -f "icon/AppIcon.icns" ]]; then
  cp "icon/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
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
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Awake.</string>
</dict>
</plist>
PLIST

if [[ -n "${APP_STORE_PROVISIONING_PROFILE:-}" ]]; then
  cp "$APP_STORE_PROVISIONING_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
fi

APP_IDENTITY="${APP_STORE_SIGNING_IDENTITY:-}"
INSTALLER_IDENTITY="${APP_STORE_INSTALLER_IDENTITY:-}"

if [[ -n "$APP_IDENTITY" ]]; then
  echo "> Signing app for Mac App Store"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$APP_IDENTITY" "$APP_PATH"
else
  echo "> No APP_STORE_SIGNING_IDENTITY set; ad-hoc signing for local sandbox checks"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --entitlements - "$APP_PATH" >/dev/null

if [[ -n "$APP_IDENTITY" && -n "$INSTALLER_IDENTITY" ]]; then
  echo "> Building signed Mac App Store package"
  productbuild --component "$APP_PATH" /Applications --sign "$INSTALLER_IDENTITY" "$PKG_PATH"
  echo "OK Mac App Store package: $PKG_PATH"
else
  echo "  Skipping .pkg export until APP_STORE_SIGNING_IDENTITY and APP_STORE_INSTALLER_IDENTITY are set"
fi

echo "OK App Store app bundle: $APP_PATH"
