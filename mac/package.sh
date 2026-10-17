#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
STAGE=$(mktemp -d "$PWD/mac/.build/release-1.0.2.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto 'outputs/GMK104 RGB Controller.app' "$STAGE/GMK104 RGB Controller.app"
ditto 'outputs/GMK104 Firmware Installer.app' "$STAGE/GMK104 Firmware Installer.app"
cp mac/README.md "$STAGE/Read Me.md"
cp mac/Firmware/README.md "$STAGE/Firmware Guide.md"
cp LICENSE "$STAGE/License.txt"
mkdir "$STAGE/Lighting Profiles"
cp mac/Resources/Profiles/*.json "$STAGE/Lighting Profiles/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname 'GMK104 Lighting Studio 1.0.2' -srcfolder "$STAGE" -ov -format UDZO 'outputs/GMK104-Lighting-Studio-1.0.2-macOS-arm64.dmg'
ditto -c -k --sequesterRsrc --keepParent 'outputs/GMK104 RGB Controller.app' 'outputs/GMK104-Lighting-Studio-1.0.2-macOS-arm64.zip'
ditto -c -k --sequesterRsrc --keepParent 'outputs/GMK104 Firmware Installer.app' 'outputs/GMK104-Firmware-Installer-1.0.2-macOS-arm64.zip'
