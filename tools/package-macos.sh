#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

READLINE_INCLUDE="$(brew --prefix readline)/include"
NATIVE_LIBS="$(sdl2-config --libs) -lSDL2_image -L$(brew --prefix readline)/lib -lreadline -lcurl -lpthread -lresolv"
make -C src/common bin CXXFLAGS_NATIVE_EXTRA="-I$READLINE_INCLUDE"
make -C src/cloudpilot embed CXXFLAGS_NATIVE_EXTRA="-I$READLINE_INCLUDE" LDFLAGS_NATIVE="$NATIVE_LIBS"
(cd MacApp && swift build -c release --scratch-path .build)

BIN_PATH="$(cd MacApp && swift build -c release --scratch-path .build --show-bin-path)"
APP="$ROOT/dist/Palm OS.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_PATH/CloudpilotMac" "$CONTENTS/MacOS/CloudpilotMac"
cp ROMs/Palm-m515-4.1-en.rom "$CONTENTS/Resources/Palm-m515-4.1-en.rom"
cp ROMs/SOURCE.md "$CONTENTS/Resources/ROM-SOURCE.md"
cp PalmApps/EudoraWeb_2.1.prc PalmApps/sslplus_1.0.7i.prc "$CONTENTS/Resources/"
cp PalmApps/SOURCE.md "$CONTENTS/Resources/BROWSER-SOURCE.md"
cp LICENSE "$CONTENTS/Resources/GPL-3.0.txt"
xcrun actool --compile "$CONTENTS/Resources" --platform macosx \
  --minimum-deployment-target 13.0 --app-icon PalmOS \
  --output-partial-info-plist "$CONTENTS/Resources/AssetCatalogInfo.plist" \
  "$ROOT/MacApp/Resources/PalmOS.icon" > /dev/null

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Palm OS Emulator</string>
  <key>CFBundleDisplayName</key><string>Palm OS Emulator</string>
  <key>CFBundleIdentifier</key><string>org.cloudpilot.mac</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>CloudpilotMac</string>
  <key>CFBundleIconFile</key><string>PalmOS</string>
  <key>CFBundleIconName</key><string>PalmOS</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

python3 tools/embed-macos-runtime.py "$CONTENTS/Frameworks"

chmod +x "$CONTENTS/MacOS/CloudpilotMac"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/Palm-OS-Emulator-macOS.zip"
echo "Created: $APP"
echo "Created: $ROOT/dist/Palm-OS-Emulator-macOS.zip"
