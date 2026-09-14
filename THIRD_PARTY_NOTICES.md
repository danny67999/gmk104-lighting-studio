# Technical references and notices

The macOS apps link Apple's system frameworks and use no third-party runtime packages. The Windows port uses Windows system APIs and .NET Framework, with no third-party runtime packages. Its firmware EXE embeds the guarded PowerShell engine and uses the Windows PowerShell runtime.

The Windows installer is built with [Inno Setup](https://jrsoftware.org/), copyright Jordan Russell and Martijn Laan; the compiler is not included in the repository. The Windows keyboard icons are original code-drawn artwork with reproducible source in `windows/Installer/IconBuilder.cs`.

The read-only AppleSMC request layout and selectors were checked against the MIT-licensed [SMCKit reference](https://github.com/beltex/SMCKit/blob/master/SMCKit/SMC.swift). CPU temperature key families were cross-checked with the [Stats sensor catalog](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) and [SoCMetrics temperature design notes](https://github.com/GoodOlClint/swift-soc-metrics/blob/main/docs/decisions/0001-die-temperature-from-smc-not-ioreport.md). The app implements its own byte-buffer reader and limits it to read operations.

Core Audio capture follows Apple's [process-tap documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). AppleSMC is undocumented and may change. Apple, macOS and ZUOYA names identify compatibility; this project is not affiliated with their owners.

The original app icon was generated with an image-generation tool. Its creation prompt is included with the source artwork.

The firmware images were transferred from this project's Windows build. They include vendor-derived firmware and are excluded from the application source-code license. No rights to unrelated vendor firmware or trademarks are granted.
