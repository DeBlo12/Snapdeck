#!/bin/bash
# Builds a release binary and wraps it into build/Snapdeck.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Snapdeck.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Snapdeck "$APP/Contents/MacOS/Snapdeck"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signing by default. Set CODESIGN_IDENTITY to a certificate from
# `security find-identity -v -p codesigning` so that macOS keeps the
# Accessibility permission across rebuilds.
# The hardened runtime stops other programs from injecting code into Snapdeck
# and so borrowing its Accessibility permission.
codesign --force --options runtime --sign "${CODESIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
