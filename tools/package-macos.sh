#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -lt 27 ]]; then
  echo "Xcode with macOS 27 SDK or newer is required (found $SDK_VERSION)" >&2
  exit 1
fi

DERIVED_DATA="$ROOT/MacApp/.build/XcodeDerivedData"
xcodebuild -project "$ROOT/MacApp/PalmOS.xcodeproj" \
  -scheme CloudpilotMac -configuration Release -destination 'platform=macOS' \
  -sdk macosx -derivedDataPath "$DERIVED_DATA" build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/Palm OS.app"
APP="$ROOT/dist/Palm OS.app"
rm -rf "$APP"
mkdir -p "$ROOT/dist"
ditto "$BUILT_APP" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Palm-OS-Emulator-macOS.zip"
echo "Created: $APP"
echo "Created: $ROOT/dist/Palm-OS-Emulator-macOS.zip"
