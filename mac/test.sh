#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p mac/.build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Tests/ProtocolTests.swift \
  -o mac/.build/ProtocolTests
mac/.build/ProtocolTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift \
  mac/Tests/LightingEffectsTests.swift -o mac/.build/LightingEffectsTests
mac/.build/LightingEffectsTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache -framework IOKit \
  mac/Sources/KeyboardEvents.swift mac/Tests/KeyboardEventTests.swift -o mac/.build/KeyboardEventTests
mac/.build/KeyboardEventTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/LightingProfile.swift \
  mac/Tests/LightingProfileTests.swift -o mac/.build/LightingProfileTests
mac/.build/LightingProfileTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  -framework IOKit -framework SwiftUI -framework AppKit -framework CoreAudio -framework AudioToolbox \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift mac/Sources/LightingProfile.swift \
  mac/Sources/HIDTransport.swift mac/Sources/KeyboardEvents.swift mac/Sources/NativeLightingInputs.swift mac/Sources/ControllerModel.swift \
  mac/Tests/ControllerModelTests.swift -o mac/.build/ControllerModelTests
mac/.build/ControllerModelTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Sources/Mapping.swift mac/Sources/LightingInputs.swift mac/Sources/LightingEffects.swift \
  mac/Tests/LightingInputsTests.swift -o mac/.build/LightingInputsTests
mac/.build/LightingInputsTests
xcrun swiftc -swift-version 5 -module-cache-path mac/.build/module-cache \
  mac/Sources/Protocol.swift mac/Firmware/Sources/FirmwarePlan.swift mac/Firmware/Tests/FirmwareTests.swift -o mac/.build/FirmwareTests
mac/.build/FirmwareTests
