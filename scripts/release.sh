#!/bin/sh
# Makes what you need to share humanpls with other people:
#   dist/humanpls-<version>.dmg   a disk image with the universal app (Apple silicon and Intel) and an Applications shortcut
#   Casks/humanpls.rb             a Homebrew cask that installs the app AND puts the `humanpls` command on the PATH
#
#   scripts/release.sh                          (the repo is read from the git remote)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/release.sh
#
# Then upload the dmg to a GitHub release tagged v<version>. The cask in this repo is a Homebrew "tap":
#   brew tap OWNER/humanpls https://github.com/OWNER/humanpls && brew install --cask humanpls
set -eu
cd "$(dirname "$0")/.."
REPO="${GITHUB_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')}"
[ -n "$REPO" ] || { echo "set GITHUB_REPO=owner/name"; exit 1; }
VERSION=$(sed -n 's/^let version = "\(.*\)"$/\1/p' Sources/humanpls/CLI.swift)
./scripts/build-app.sh release
rm -rf dist && mkdir -p dist Casks
DMG="dist/humanpls-$VERSION.dmg"
STAGE=$(mktemp -d)
ditto build/humanpls.app "$STAGE/humanpls.app"            # ditto keeps the signature intact
ln -s /Applications "$STAGE/Applications"                  # the "drag to Applications" shortcut
hdiutil create -volname "humanpls" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
cat > Casks/humanpls.rb <<RB
cask "humanpls" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/humanpls-#{version}.dmg"
  name "humanpls"
  desc "Native macOS popup that lets an AI agent ask you to pick between options"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :sonoma"

  app "humanpls.app"
  # puts the command on the PATH: no manual step
  binary "#{appdir}/humanpls.app/Contents/MacOS/humanpls"

  zap trash: "~/Library/Application Support/humanpls"
end
RB
echo "built $DMG ($SHA)"
echo "cask:  Casks/humanpls.rb   (repo: $REPO)"
if [ -z "${SIGN_IDENTITY:-}" ]; then
  echo "note: the app is signed ad hoc. macOS Gatekeeper will warn people who download it (right click > Open once)."
  echo "      With an Apple Developer ID: SIGN_IDENTITY=... scripts/release.sh, then notarize: xcrun notarytool submit $DMG --wait && xcrun stapler staple $DMG"
fi
