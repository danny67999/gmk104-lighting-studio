#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="$PWD/outputs/GMK104 Firmware Installer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" mac/.build/module-cache
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -c mac/Firmware/Native/AuthorizationLauncher.c \
  -o mac/.build/FirmwareAuthorizationLauncher.o
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 \
  -import-objc-header mac/Firmware/Native/AuthorizationLauncher.h mac/.build/FirmwareAuthorizationLauncher.o \
  -module-cache-path "$PWD/mac/.build/module-cache" \
  -framework SwiftUI -framework AppKit -framework IOKit -framework Security \
  mac/Sources/Protocol.swift mac/Sources/HIDTransport.swift mac/Firmware/Sources/*.swift \
  -o "$APP/Contents/MacOS/GMK104FirmwareInstaller"
# A clean bundle contains only firmware published before 1.0 plus the 1.0 image.
rm -f "$APP/Contents/Resources/"*.bin
for image in GMK104-firmware-1.0.bin GMK104-custom-RGB-v0.2-experimental.bin GMK104-custom-RGB-v0.3-experimental.bin GMK104-custom-RGB-v0.4-experimental.bin GMK104-stock-recovery.bin; do
  cp "mac/Firmware/Resources/$image" "$APP/Contents/Resources/"
done
cp mac/Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gmk104.firmwareinstaller</string>
<key>CFBundleName</key><string>GMK104 Firmware Installer</string>
<key>CFBundleExecutable</key><string>GMK104FirmwareInstaller</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>21</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
