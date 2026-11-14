#!/bin/sh
# Builds build/humanpls.app: the menu bar app and the CLI in one bundle.
#   scripts/build-app.sh            release build, universal (Apple silicon and Intel)
#   scripts/build-app.sh debug      debug build (faster, this Mac only)
# Signing: ad hoc by default. For a Developer ID signature, set SIGN_IDENTITY="Developer ID Application: Name (TEAMID)".
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION=$(sed -n 's/^let version = "\(.*\)"$/\1/p' Sources/humanpls/CLI.swift)
if [ "$CONFIG" = "release" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/humanpls"      # where SwiftPM puts it depends on the version
else
  swift build -c "$CONFIG"
  BIN=".build/$CONFIG/humanpls"
fi
APP="build/humanpls.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
touch build/.metadata_never_index      # keep Spotlight from listing this build copy next to the installed app
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
xattr -cr "$APP" 2>/dev/null || true      # no extended attributes inside the bundle (they end up as ._ files in a zip)
IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "signed (ad hoc)" || echo "note: codesign failed, the app still runs"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP" && echo "signed with: $IDENTITY"
fi
lipo -info "$APP/Contents/MacOS/humanpls" 2>/dev/null | sed 's/^/architectures: /' 
echo "built $APP ($VERSION, $CONFIG)"
