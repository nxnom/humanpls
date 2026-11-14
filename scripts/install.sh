#!/bin/sh
# Builds the app, puts it in ~/Applications and links the `humanpls` command into ~/.local/bin.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh release
DEST="$HOME/Applications"
mkdir -p "$DEST"
"$DEST/humanpls.app/Contents/MacOS/humanpls" quit >/dev/null 2>&1 || true
rm -rf "$DEST/humanpls.app"
cp -R build/humanpls.app "$DEST/humanpls.app"
"$DEST/humanpls.app/Contents/MacOS/humanpls" install-cli
echo "installed $DEST/humanpls.app"
echo "try: humanpls --version"
