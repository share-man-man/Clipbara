#!/bin/bash
# Build ClipbaraLocal (the Local configuration: optimized, signed with your own
# team from Config/Local.xcconfig, no self-update) and install it to /Applications.
# Usage: bash scripts/install-local.sh
set -euo pipefail

# Repository root
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Product name of the Local configuration (project.yml)
APP_NAME="ClipbaraLocal"
# Separate DerivedData so this never touches the Debug build products
DERIVED="$ROOT/build/local/DerivedData"
# Built app bundle
BUILT_APP="$DERIVED/Build/Products/Local/$APP_NAME.app"
# Installed app bundle
INSTALLED_APP="/Applications/$APP_NAME.app"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$ROOT"

if [ ! -f Config/Local.xcconfig ]; then
    echo "    WARNING: Config/Local.xcconfig is missing, so the app is signed ad-hoc."
    echo "    macOS will drop the Accessibility grant after every rebuild."
    echo "    Copy Config/Local.xcconfig.example and set your team ID to avoid that."
fi

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building $APP_NAME (Local)..."
xcodebuild \
    -project Clipbara.xcodeproj \
    -scheme Clipbara \
    -configuration Local \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    build \
    | tail -5
test -d "$BUILT_APP"

echo "==> Quitting the running $APP_NAME..."
# Match only this app's executable, never the release Clipbara or ClipbaraDev
pkill -f "$APP_NAME.app/Contents/MacOS/" || true
sleep 1

echo "==> Installing to $INSTALLED_APP..."
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

echo "==> Launching..."
open "$INSTALLED_APP"
echo "    Done. Version $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INSTALLED_APP/Contents/Info.plist")"
