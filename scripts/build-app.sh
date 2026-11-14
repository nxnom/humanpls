#!/bin/sh
# Builds build/humanpls.app: the menu bar app and the CLI in one bundle.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build (faster)
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION=$(sed -n 's/^let version = "\(.*\)"$/\1/p' Sources/humanpls/CLI.swift)
swift build -c "$CONFIG"
BIN=".build/$CONFIG/humanpls"
APP="build/humanpls.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/humanpls"
cp design/logo/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"     # made by scripts/make-logo.py
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>humanpls</string>
  <key>CFBundleDisplayName</key><string>humanpls</string>
  <key>CFBundleIdentifier</key><string>dev.humanpls.app</string>
  <key>CFBundleExecutable</key><string>humanpls</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>humanpls</string>
</dict>
</plist>
PLIST
# ad-hoc signature: gives the app a stable identity for macOS permissions
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "signed (ad hoc)" || echo "note: codesign failed, the app still runs"
echo "built $APP ($VERSION, $CONFIG)"
