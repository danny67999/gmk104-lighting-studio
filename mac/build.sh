#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/outputs/GMK104 RGB Controller.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" mac/.build/module-cache
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 \
  -module-cache-path "$PWD/mac/.build/module-cache" \
  -framework SwiftUI -framework AppKit -framework IOKit -framework CoreAudio -framework AudioToolbox \
  mac/Sources/*.swift -o "$APP/Contents/MacOS/GMK104RGBController"
cp mac/Resources/*.json "$APP/Contents/Resources/"
cp mac/Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gmk104.rgbcontroller</string>
<key>CFBundleName</key><string>GMK104 RGB Controller</string>
<key>CFBundleExecutable</key><string>GMK104RGBController</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.1</string>
<key>CFBundleVersion</key><string>11</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSAudioCaptureUsageDescription</key><string>React keyboard lighting to audio playing on your Mac. Audio is analyzed locally and is never recorded or uploaded.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
