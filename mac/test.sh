#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p mac/.build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Tests/ProtocolTests.swift \
  -o mac/.build/ProtocolTests
mac/.build/ProtocolTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift \
  mac/Tests/LightingEffectsTests.swift -o mac/.build/LightingEffectsTests
mac/.build/LightingEffectsTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache -framework IOKit \
  mac/Sources/BluetoothIdentity.swift mac/Sources/KeyboardEvents.swift mac/Tests/KeyboardEventTests.swift -o mac/.build/KeyboardEventTests
mac/.build/KeyboardEventTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache -framework IOKit \
  mac/Sources/Protocol.swift mac/Sources/HIDTransport.swift mac/Tests/HIDSelectionTests.swift -o mac/.build/HIDSelectionTests
mac/.build/HIDSelectionTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift mac/Sources/LightingProfile.swift \
  mac/Tests/LightingProfileTests.swift -o mac/.build/LightingProfileTests
mac/.build/LightingProfileTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift \
  mac/Sources/LightingProfile.swift mac/Sources/OnboardProfile.swift mac/Tests/OnboardProfileTests.swift -o mac/.build/OnboardProfileTests
mac/.build/OnboardProfileTests
xcrun clang -std=c11 -Wall -Wextra -Werror \
  mac/Firmware/Patches/native_ripple/onboard_profile.c \
  mac/Firmware/Patches/native_ripple/test_onboard_profile.c \
  -o mac/.build/OnboardProfileParserTests
mac/.build/OnboardProfileParserTests
xcrun clang -std=c11 -Wall -Wextra -Werror \
  mac/Firmware/Patches/native_ripple/onboard_profile.c \
  mac/Firmware/Patches/native_ripple/onboard_upload_device.c \
  mac/Firmware/Patches/native_ripple/test_onboard_upload_device.c \
  -o mac/.build/OnboardUploadDeviceTests
mac/.build/OnboardUploadDeviceTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift \
  mac/Sources/LightingProfile.swift mac/Sources/OnboardProfile.swift mac/Sources/OnboardUploader.swift mac/Sources/OnboardTelemetry.swift \
  mac/Tests/OnboardUploaderTests.swift -o mac/.build/OnboardUploaderTests
mac/.build/OnboardUploaderTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  -framework IOKit -framework SwiftUI -framework AppKit -framework CoreAudio -framework AudioToolbox \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift mac/Sources/LightingProfile.swift mac/Sources/OnboardProfile.swift mac/Sources/OnboardUploader.swift \
  mac/Sources/HIDTransport.swift mac/Sources/BluetoothIdentity.swift mac/Sources/BluetoothPackets.swift mac/Sources/BluetoothTransport.swift mac/Sources/KeyboardPreferences.swift mac/Sources/KeyboardEvents.swift mac/Sources/NativeLightingInputs.swift mac/Sources/ControllerModel.swift mac/Sources/LightingPresets.swift \
  mac/Tests/ControllerModelTests.swift -o mac/.build/ControllerModelTests
mac/.build/ControllerModelTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/KeySelection.swift mac/Tests/KeySelectionTests.swift -o mac/.build/KeySelectionTests
mac/.build/KeySelectionTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift \
  mac/Tests/LightingInputsTests.swift -o mac/.build/LightingInputsTests
mac/.build/LightingInputsTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Firmware/Sources/FirmwarePlan.swift mac/Firmware/Tests/FirmwareTests.swift -o mac/.build/FirmwareTests
mac/.build/FirmwareTests
xcrun clang -mmacosx-version-min=13.0 -c mac/Firmware/Native/AuthorizationLauncher.c \
  -o mac/.build/FirmwareAuthorizationLauncher-tests.o
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  -import-objc-header mac/Firmware/Native/AuthorizationLauncher.h mac/.build/FirmwareAuthorizationLauncher-tests.o \
  -framework AppKit -framework IOKit -framework Security \
  mac/Sources/Protocol.swift mac/Sources/HIDTransport.swift mac/Firmware/Sources/FirmwarePlan.swift \
  mac/Firmware/Sources/FirmwareDevice.swift mac/Firmware/Sources/FirmwareStorageSurvey.swift mac/Firmware/Sources/FirmwareAuthorization.swift \
  mac/Firmware/Tests/AuthorizationTests.swift -o mac/.build/AuthorizationTests
mac/.build/AuthorizationTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/BluetoothPackets.swift mac/Sources/KeyboardPreferences.swift \
  mac/Tests/WirelessSettingsTests.swift -o mac/.build/WirelessSettingsTests
mac/.build/WirelessSettingsTests
python3 mac/Firmware/Patches/test_wireless.py
python3 mac/Firmware/Patches/test_streaming.py
python3 mac/Firmware/Patches/native_ripple/test_native_ripple.py
python3 mac/Firmware/Patches/native_ripple/test_native_ripple_v06.py
sh mac/Firmware/Patches/native_ripple/renderer_test.sh
sh mac/Firmware/Patches/onboard_storage/test.sh
sh mac/Firmware/Patches/onboard_runtime/test.sh
sh mac/Firmware/Patches/onboard_persistent/test.sh
sh mac/Firmware/Patches/onboard_persistent/test_performance.sh
sh mac/Firmware/Patches/onboard_persistent/test_reactive.sh
sh mac/Firmware/Patches/onboard_persistent/test_matrix.sh
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift mac/Tests/MatrixRainTests.swift -o mac/.build/MatrixRainTests
mac/.build/MatrixRainTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Firmware/Sources/FirmwarePlan.swift \
  mac/Firmware/Sources/FirmwareStorageSurvey.swift mac/Firmware/Tests/FirmwareStorageSurveyTests.swift \
  -o mac/.build/FirmwareStorageSurveyTests
mac/.build/FirmwareStorageSurveyTests

sh mac/Firmware/Patches/onboard_persistent/test_matrix_columns.sh
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/MatrixRain.swift mac/Sources/LogicalMatrix.swift mac/Tests/MatrixColumnsTests.swift -o mac/.build/MatrixColumnsTests
mac/.build/MatrixColumnsTests

sh mac/Firmware/Patches/onboard_persistent/test_aurora.sh
