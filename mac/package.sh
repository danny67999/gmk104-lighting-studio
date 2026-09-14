#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE="$PWD/mac/.build/release-staging"
mkdir -p "$STAGE"
ditto 'outputs/GMK104 RGB Controller.app' "$STAGE/GMK104 RGB Controller.app"
ditto 'outputs/GMK104 Firmware Installer.app' "$STAGE/GMK104 Firmware Installer.app"
cp mac/README.md "$STAGE/Read Me.md"
cp LICENSE THIRD_PARTY_NOTICES.md "$STAGE/"
cp mac/Firmware/README.md "$STAGE/Firmware Guide.md"
ln -sfn /Applications "$STAGE/Applications"
hdiutil create -volname 'GMK104 Lighting Studio 1.4.1' -srcfolder "$STAGE" -ov -format UDZO 'outputs/GMK104-Lighting-Studio-1.4.1-macOS-arm64.dmg'
ditto -c -k --sequesterRsrc --keepParent 'outputs/GMK104 RGB Controller.app' 'outputs/GMK104-Lighting-Studio-1.4.1-macOS-arm64.zip'
ditto -c -k --sequesterRsrc --keepParent 'outputs/GMK104 Firmware Installer.app' 'outputs/GMK104-Firmware-Installer-1.0.0-macOS-arm64.zip'
(cd outputs && shasum -a 256 GMK104-Lighting-Studio-1.4.1-macOS-arm64.dmg GMK104-Lighting-Studio-1.4.1-macOS-arm64.zip GMK104-Firmware-Installer-1.0.0-macOS-arm64.zip > SHA256SUMS.txt)
