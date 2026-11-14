#!/bin/sh
# Builds the app, installs it in /Applications (or ~/Applications when that is not writable) and links the
# `humanpls` command. Older copies in the other place are removed, so there is only ever one humanpls.app.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh release
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
# stop a running copy, then replace
for d in /Applications "$HOME/Applications"; do
  [ -x "$d/humanpls.app/Contents/MacOS/humanpls" ] && "$d/humanpls.app/Contents/MacOS/humanpls" quit >/dev/null 2>&1 || true
done
rm -rf /Applications/humanpls.app "$HOME/Applications/humanpls.app"      # only one copy, wherever the old one was
ditto build/humanpls.app "$DEST/humanpls.app"
"$DEST/humanpls.app/Contents/MacOS/humanpls" install-cli
rm -rf build/humanpls.app        # the build copy is not needed any more (and Spotlight would list it)
echo "installed $DEST/humanpls.app"
echo "try: humanpls --version"
