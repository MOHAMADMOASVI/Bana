#!/bin/zsh
# Builds a Release .app and packs it into a drag-to-Applications DMG.
# Usage: Scripts/make-dmg.sh   →  dist/ProjectLauncher-<version>.dmg
set -euo pipefail
cd "${0:A:h}/.."

APP_NAME=ProjectLauncher
xcodebuild -project $APP_NAME.xcodeproj -scheme $APP_NAME -configuration Release \
  -derivedDataPath build -destination 'generic/platform=macOS' build -quiet
APP="build/Build/Products/Release/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Project Launcher.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
DMG="dist/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Project Launcher" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "$PWD/$DMG"
