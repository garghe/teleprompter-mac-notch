#!/usr/bin/env bash
# Builds NotchPrompter.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/NotchPrompter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchPrompter" "$APP/Contents/MacOS/NotchPrompter"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS will run it locally.
codesign --force --sign - "$APP"

echo "Built $APP"
