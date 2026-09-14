#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="$PWD/outputs/GMK104 Firmware Installer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" mac/.build/module-cache
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 \
  -module-cache-path "$PWD/mac/.build/module-cache" \
  -framework SwiftUI -framework AppKit -framework IOKit \
  mac/Sources/Protocol.swift mac/Sources/HIDTransport.swift mac/Firmware/Sources/*.swift \
  -o "$APP/Contents/MacOS/GMK104FirmwareInstaller"
cp mac/Firmware/Resources/*.bin "$APP/Contents/Resources/"
cp mac/Resources/AppIcon.icns "$APP/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gmk104.firmwareinstaller</string>
<key>CFBundleName</key><string>GMK104 Firmware Installer</string>
<key>CFBundleExecutable</key><string>GMK104FirmwareInstaller</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
