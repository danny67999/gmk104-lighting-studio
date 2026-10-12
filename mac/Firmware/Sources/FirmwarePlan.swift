import Foundation
import CryptoKit

enum FirmwareTarget: String, CaseIterable, Identifiable, Codable {
    case custom, wireless, streaming, nativeRipple, nativeRippleFixed, stock, persistentLighting, storageDiagnosticRollback, performanceLighting, reactiveLighting, matrixLighting, matrixRainFixed, matrixRainStaggered, matrixRainVertical, matrixColumns, auroraLighting
    #if GMK104_V07_LOCAL_TEST
    case onboardProfilePreview
    #endif
    #if GMK104_V08_LOCAL_TEST
    case storageSurvey
    #endif
    // Freeze the public catalog independently from legacy identity recognition.
    static let publishedCases: [Self] = [.auroraLighting, .custom, .wireless, .streaming, .stock]
    var id: String { rawValue }
    var name: String {
        switch self {
        case .auroraLighting: return "Complete lighting firmware 1.0"
        case .matrixColumns: return "Persistent lighting v1.7 — spaced Matrix and key rain"
        case .matrixRainVertical: return "Persistent lighting v1.6 — vertical video-style Matrix"
        case .matrixRainStaggered: return "Persistent lighting v1.5 — staggered Matrix rain"
        case .matrixRainFixed: return "Persistent lighting v1.4 — vertical Matrix rain"
        case .matrixLighting: return "Persistent lighting v1.3 — Matrix rain"
        case .reactiveLighting: return "Persistent lighting v1.2 — reactive effects"
        case .performanceLighting: return "Persistent lighting v1.1 — ripple performance"
        case .persistentLighting: return "Persistent lighting v1.0"
        case .storageDiagnosticRollback: return "Restore previous v0.8"
        case .custom: return "Custom RGB v0.2"
        case .wireless: return "Wireless + sleep v0.3 (experimental)"
        case .streaming: return "Faster Bluetooth v0.4 (experimental)"
        case .nativeRipple: return "On-keyboard rainbow ripple v0.5 (retired)"
        case .nativeRippleFixed: return "On-keyboard rainbow ripple v0.6 (experimental)"
        case .stock: return "Stock firmware"
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview: return "On-keyboard profiles v0.7 (RAM-only local test)"
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return "Read-only storage survey v0.8 (local test)"
        #endif
        }
    }
    var file: String {
        switch self {
        case .auroraLighting: return "GMK104-firmware-1.0.bin"
        case .matrixColumns: return "GMK104-matrix-lighting-v1.7.bin"
        case .matrixRainVertical: return "GMK104-matrix-lighting-v1.6.bin"
        case .matrixRainStaggered: return "GMK104-matrix-lighting-v1.5.bin"
        case .matrixRainFixed: return "GMK104-matrix-lighting-v1.4.bin"
        case .matrixLighting: return "GMK104-matrix-lighting-v1.3.bin"
        case .reactiveLighting: return "GMK104-reactive-lighting-v1.2.bin"
        case .performanceLighting: return "GMK104-persistent-lighting-v1.1.bin"
        case .persistentLighting: return "GMK104-persistent-lighting-v1.0.bin"
        case .storageDiagnosticRollback: return "GMK104-v0.8-READ-ONLY-DIAGNOSTIC.bin"
        case .custom: return "GMK104-custom-RGB-v0.2-experimental.bin"
        case .wireless: return "GMK104-custom-RGB-v0.3-experimental.bin"
        case .streaming: return "GMK104-custom-RGB-v0.4-experimental.bin"
        case .nativeRipple: return "GMK104-onboard-ripple-v0.5-experimental.bin"
        case .nativeRippleFixed: return "GMK104-onboard-ripple-v0.6-experimental.bin"
        case .stock: return "GMK104-stock-recovery.bin"
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview: return "GMK104-v0.7-RAM-only-local-test.bin"
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return "GMK104-v0.8-READ-ONLY-DIAGNOSTIC.bin"
        #endif
        }
    }
    var imageSize: Int {
        if self == .auroraLighting { return 174372 }
        if self == .matrixColumns { return 174164 }
        if self == .matrixRainVertical { return 172980 }
        if self == .matrixRainStaggered { return 173236 }
        if self == .matrixRainFixed { return 173332 }
        if self == .matrixLighting { return 173204 }
        if self == .reactiveLighting { return 172404 }
        if self == .performanceLighting { return 171700 }
        if self == .persistentLighting { return 167252 }
        if self == .storageDiagnosticRollback { return 159588 }
        #if GMK104_V07_LOCAL_TEST
        if self == .onboardProfilePreview { return 159124 }
        #endif
        #if GMK104_V08_LOCAL_TEST
        if self == .storageSurvey { return 159588 }
        #endif
        return (self == .nativeRipple || self == .nativeRippleFixed) ? 147156 : ((self == .wireless || self == .streaming) ? 142820 : 140244)
    }
    var crc: UInt32 {
        switch self {
        case .auroraLighting: return 0x7F2F4310
        case .matrixColumns: return 0x193BCBFA
        case .matrixRainVertical: return 0xD725D89A
        case .matrixRainStaggered: return 0xA86B6815
        case .matrixRainFixed: return 0xB27DBFBE
        case .matrixLighting: return 0x9066E8DB
        case .reactiveLighting: return 0x37E8F32B
        case .performanceLighting: return 0x938EFC28
        case .persistentLighting: return 0xD51110C3
        case .storageDiagnosticRollback: return 0xB6EA62D8
        case .custom: return 0xC6342859
        case .wireless: return 0x060C4E9E
        case .streaming: return 0x6F0AD0C1
        case .nativeRipple: return 0x6CF41421
        case .nativeRippleFixed: return 0x89EEE309
        case .stock: return 0xB85531A2
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview: return 0xD79CC2E1
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return 0xB6EA62D8
        #endif
        }
    }
    var hash: String {
        switch self {
        case .auroraLighting: return "4BDC3E9729A0583F2DAEA150FA1CCF4374C5115046F3B8F0655A4758B1DFE22E"
        case .matrixColumns: return "4B1FF3A4760FCE95E4C75B24D2622B3389603614AC8AB4642897CD6FFC35D4C0"
        case .matrixRainVertical: return "D9C91C34D8618A852F1671D431F31A30B234406BC18B6880F0B8761AC75E6F0F"
        case .matrixRainStaggered: return "6840328B21009A05D37495AE13EF7BC51AA1A027F3542CBC8373918A5A314D31"
        case .matrixRainFixed: return "477D9C42D507119B3605DAC04D482CC6937F0FEF7FB1EDF5DF553E523F9CC124"
        case .matrixLighting: return "1FE7B5DFAAFF446A6FE325BEA193BBE8BB79E53C470A54EDDE4341A65150EF1F"
        case .reactiveLighting: return "C7701C632C9675F2056EBF23D458453769BFD2D6E2B794021D66F38ED935D973"
        case .performanceLighting: return "85031A1B48D2CFAAE3452D796BF2D2BA68D9B73B0F400B8CCE630D3161645106"
        case .persistentLighting: return "3980487576ADEB2A682C205309E523BEE7D42030D6525EFF368FE7296ABA2DA8"
        case .storageDiagnosticRollback: return "005DFCBCA508610AFE4231BE3AEC4399572B8CF765B9CD8BE4696F3D705AB507"
        case .custom: return "96E431887F574CBE01E900FF08A803D8351EDE421A982809E294F34B1E7F0FD4"
        case .wireless: return "CFB5604E1B861948078C0176801A74EF45727C96225145DA82B25FB81B96DD8A"
        case .streaming: return "11DB2CD854381021B45C0B025D7FABC5277CDBFED185A4E8AF0E9327D7ACC347"
        case .nativeRipple: return "DB44BDBAB849F041C1EE44E3317D3B8E6DC9BD483C691B98F1D5C5011450EBF4"
        case .nativeRippleFixed: return "5A656E2295EC69D20562B11478F5CBF6D0F732D9C7E04C1C4A6B95EDEFC2FF51"
        case .stock: return "FD6E3E8B9D67E2E4942634FCB5C44275F1B1B4F6975F1691318C5A1D44E1661F"
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview: return "871E0AFEC8C22B80432A703A8F4773CAF7A0D59494EBE18B1D00BF1B0DFDF027"
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return "005DFCBCA508610AFE4231BE3AEC4399572B8CF765B9CD8BE4696F3D705AB507"
        #endif
        }
    }
    var streamHash: String {
        switch self {
        case .auroraLighting: return "CCD0EC6A43F3EBBF2FF84AA1A95F79DB300D8076ED1C5853E9345B51A1F3689E"
        case .matrixColumns: return "95D534B65211D564B75C5D46DC35DE8E00C64FDF58C33FE81C2A3B2033416E30"
        case .matrixRainVertical: return "9706AD2025AAE5F3AF81556BE5A25A49120FC00897937EB4D26B9B2A8FEE066A"
        case .matrixRainStaggered: return "685617CA416CDF22B4A7D986292208F15BA8C9C9F4BC1233FD706E4F8DBC5A89"
        case .matrixRainFixed: return "888CB29EB03BCFF0E5CEBC1F424082A77EDFF42275BAAC58E5FB2302FBDAD628"
        case .matrixLighting: return "93E9138E4D79AE909DA3881B05416E95EEDEE127DF35C253ACB551111F2FD1EE"
        case .reactiveLighting: return "1DC646B6DEDA5284E95F0F0820B7A4B5AF2D2298B096154CCACF93AEB0A8B05B"
        case .performanceLighting: return "0E6DE3244AB25898B50ECE7092C6276CC16B8FFCC3245596FCD0FAF96F7C0334"
        case .persistentLighting: return "6F1512CC3D27DF21EB62806575E9329EFA5F7310934BCA7C00E00C8D5C53B419"
        case .storageDiagnosticRollback: return "C3B0193F942F7C98E419278E20AE627CB2C0EAE85514F3893B7CBF403ECD452A"
        case .custom: return "1565181114783AB9ED0E12EE4A5CC1366DD1412A1F36FEE7628926140377C0A7"
        case .wireless: return "D2847D4B445AA3D71DEA6F9479B77ADD70DAFC10BF570704D9793B91E89A9D77"
        case .streaming: return "87005D5D7E249C731B135923A447DA28A30514DD7FDB3BB1546C3471132E2C57"
        case .nativeRipple: return "7592C2F35D1919C7080A47B3F49F6ECA3EBB9B564574B8404A4B4C02DCD0B1F0"
        case .nativeRippleFixed: return "B72CF02A5F50BBF1DF90A5D31815691252A45614206F5CAE34C25EFE2E293D85"
        case .stock: return "818CF184FCE29532363DF592AAE2ADAAAB0AFEA345D99667240E5BA96302950A"
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview: return "D86E1DBA8A35EF10D8A82C68A3575D92D12DA231C6E54370310933D827055DC4"
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return "C3B0193F942F7C98E419278E20AE627CB2C0EAE85514F3893B7CBF403ECD452A"
        #endif
        }
    }
    var paddedHash: String {
        switch self {
        case .auroraLighting: return "B72D6B4BD9C3D70683548B0FF094560218697787862895AAB5DB22FA9650F232"
        case .matrixColumns: return "AF99CD1547C2F220C41C6A1B33CC97D4E2E6AF42E74BF587E8AB5A2F81E7D530"
        case .matrixRainVertical: return "8DC826BA8C7B49BE81EDB04B90D1AE6B5B1455E6E6E45FED0F85DE3AD810C1CA"
        case .matrixRainStaggered: return "8BB181D2BE3FFBD63D8833DB61BFDB0CA4E62493E0C8343E4BB4DDEFA466CB07"
        case .matrixRainFixed: return "308303FA16FA6FA46B5689E126DCE94CBA5A3219A2EAEB9D1D09830893289E52"
        case .matrixLighting: return "B2968BB9999F1937EB5FC68FA96C49135AEA54429F8449A51DFB6D67F1C81C99"
        case .reactiveLighting: return "C2519DE69D8F912EE4DFD65B4E6AC1530DDF84D63D7C388758B62E3C81ADA6B8"
        case .performanceLighting: return "216E3AC1B7CAB468D1ADE502BA9FA11AAFC499BB7F382FEF122C3D9516C87D2A"
        case .persistentLighting: return "EE23C88602B48CB4087271706FCB41915178D6A55B4BA84D15CE02DFCEEDFF45"
        case .storageDiagnosticRollback: return "1FE44A4E6501408A3CBFF8A06901BC6245F4D28954EC076275D4293A23E1D251"
        case .custom: return "C68E839209350A16D4802533C204E49DF3201E5F59F6BB74FC1602BB2D5FCB91"
        case .wireless: return "439608D8FE9AD55280972047820EC7CD2BB586BEA4F1CB654BB54A3A11B47A1F"
        case .streaming: return "1610D752A299D26CEFE6A744FAE900AC3C1EB877210217A808238526542F8976"
        case .nativeRipple: return "4A124D6CC0039331F88FB5CE1F328136AD11A341961947056F5A39625942C8EA"
        case .nativeRippleFixed: return "2451D324DA5BCF7F234393A582CBCABC02602D9810AD316C340B0F254F930981"
        case .stock: return "484FA932018A18A22EA7E536D07F0B19A27DBE5D0F8F8B24E9BFD3A495F3BFD7"
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview: return "64B33E9E071ECF4E22C79408C26F0471508C93A2FEB2F7D8AA8EAE3C1D0D8C38"
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return "1FE44A4E6501408A3CBFF8A06901BC6245F4D28954EC076275D4293A23E1D251"
        #endif
        }
    }
    var phrase: String {
        switch self {
        case .auroraLighting: return "INSTALL GMK104 LIGHTING 7F2F4310"
        case .matrixColumns: return "INSTALL GMK104 MATRIX 193BCBFA"
        case .matrixRainVertical: return "INSTALL GMK104 MATRIX D725D89A"
        case .matrixRainStaggered: return "INSTALL GMK104 MATRIX A86B6815"
        case .matrixRainFixed: return "INSTALL GMK104 MATRIX B27DBFBE"
        case .matrixLighting: return "INSTALL GMK104 MATRIX 9066E8DB"
        case .reactiveLighting: return "INSTALL GMK104 REACTIVE 37E8F32B"
        case .performanceLighting: return "INSTALL GMK104 PERFORMANCE 938EFC28"
        case .persistentLighting: return "INSTALL GMK104 PERSISTENT D51110C3"
        case .storageDiagnosticRollback: return "RESTORE GMK104 PREVIOUS B6EA62D8"
        case .custom: return "FLASH GMK104 CUSTOM C6342859"
        case .wireless: return "TEST GMK104 WIRELESS 060C4E9E"
        case .streaming: return "TEST GMK104 BLUETOOTH 6F0AD0C1"
        case .nativeRipple: return "RETIRED GMK104 NATIVE RIPPLE 6CF41421"
        case .nativeRippleFixed: return "TEST GMK104 NATIVE RIPPLE 89EEE309"
        case .stock: return "RESTORE GMK104 STOCK B85531A2"
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview: return "TEST RAM ONLY GMK104 D79CC2E1"
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return "TEST READ ONLY GMK104 B6EA62D8"
        #endif
        }
    }
    var detail: String {
        switch self {
        case .auroraLighting: return "Complete firmware correcting Aurora to match the app preview: drifting green/cyan sine folds, bright bands and dim gaps, with matching speed. Retains all effects through ID26, sixteen layers, existing mapping and guarded persistent profile storage. Installs over the recognized stock/custom releases and persistent local versions through v1.7; compatible profiles restore without rewriting. Offline renderer, storage and packet checks passed; physical boot, typing and power-cycle checks still require installation. A failed boot could require hardware recovery."
        case .matrixColumns: return "Complete firmware adding Spaced matrix rain (fixed odd columns with dark even columns) and Matrix key rain (press-triggered falling trails). Fixed key groups follow the keyboard across all 104 keys. All previous effects, sixteen layers, adjustable speed/color and guarded persistent storage remain. Requires verified installed persistent v1.0 through v1.6. Compatible saved profiles restore without rewriting. Offline checks pass; physical boot, typing and power-cycle validation remain required. Failed boot may require hardware recovery."
        case .matrixRainVertical: return "Complete firmware matching the supplied horizontal streak reference, rotated vertically: white leading heads, continuous colored fading tails, moving dark spaces and staggered columns. Automatic top-to-bottom looping with adjustable speed/color. All previous effects, sixteen layers and guarded persistent storage remain. Requires verified installed v1.0 through v1.5. Compatible saved profiles restore without rewriting. Offline checks pass; physical boot, typing and power-cycle validation remain required. Failed boot may require hardware recovery."
        case .matrixRainStaggered: return "Complete firmware with Matrix streams that enter on lit top-row heads, skip every other trail row and stagger moving gaps between neighboring columns. Automatic playback, adjustable speed/color, all previous effects, sixteen layers and guarded persistent storage. Requires verified installed v1.0, v1.1, v1.2, v1.3 or v1.4. Compatible saved profiles restore without rewriting. Offline checks pass; physical boot, typing and power-cycle validation remain required. Failed boot may require hardware recovery."
        case .matrixRainFixed: return "Complete firmware with vertical Matrix rain: randomly missing cells travel down fixed columns, with varied brightness, colored fading trails and independent timing. Includes all previous effects, sixteen layers and the unchanged guarded persistent profile storage. Requires verified installed v1.0, v1.1, v1.2 or v1.3. Saved compatible profiles restore without rewriting. Speed and color remain adjustable per layer. Offline checks pass; physical boot, typing and power-cycle validation remain required. Failed boot may require hardware recovery."
        case .matrixLighting: return "Complete firmware with automatic Matrix rain, bright heads, fading colored trails and independent column timing, plus all existing effects and sixteen layers. Speed and color are set per layer. Uses the same bounded rendering and guarded persistent storage as v1.2. Requires verified installed v1.0, v1.1 or v1.2. Saved supported profiles restore without rewriting. Save a profile without Matrix rain before rollback to v1.2. Offline checks pass; physical typing, lighting and power-cycle validation are still required. A failed boot could require hardware recovery."
        case .reactiveLighting: return "Complete firmware with Key Toggle, Rainbow Reactive, Splash, Cross Ripple, Row Wave and Column Wave, plus existing effects and sixteen layers. Hold uses press/release; Toggle uses successive presses and ignores repeats. Uses the same guarded storage and bounded rendering as v1.1. Requires installed v1.0 or v1.1. Saved profiles are restored without rewriting them. New effects require this firmware; older firmware cannot play profiles containing them. Offline checks pass; physical typing, lighting and power-cycle tests are still required. A failed boot could require hardware recovery."
        case .performanceLighting: return "Complete persistent-lighting firmware with all effects and sixteen layers. Ripple calculations and frame drawing now run in bounded batches with native arithmetic, giving the stock keyboard loop time between batches. Existing saved profiles use the same storage format and are restored without rewriting them. Requires persistent v1.0 first; rollback to v1.0 requires responsive USB. Offline parity, instruction-budget and storage tests pass; actual typing latency still needs target validation. A failed boot could require hardware recovery."
        case .persistentLighting: return "Runs all Studio/manual effects, up to 16 layers and independent speeds on the keyboard. Save to keyboard stores the complete profile and brightness for automatic startup after power removal. Save uses wired USB. The full image passed offline tests; physical power-cycle and wireless validation are still required. This guarded flash allocation is reverse engineered, and a failed boot could require hardware recovery. Requires the verified v0.8 image first."
        case .storageDiagnosticRollback: return "Restores the exact v0.8 firmware currently verified on the owner's keyboard. Its profiles run in RAM and disappear on power loss. This rollback requires responsive USB and does not erase saved profile sectors."
        case .custom: return "The direct RGB firmware previously tested on this keyboard. Installs over stock or rolls back experimental v0.3/v0.4."
        case .wireless: return "Adds Bluetooth lighting and adjustable wireless sleep. Its first wired boot and Bluetooth connection passed on the test Mac. Bluetooth animation is slow. Installs over v0.2 or rolls back v0.4."
        case .streaming: return "Enables faster Bluetooth frame transfers with Lighting Studio 1.5.2. Changes one characteristic property byte plus the image CRC; executable code is identical to v0.3. Physical throughput and boot are not yet tested. Requires v0.3 first. Refresh Bluetooth pairing after installation."
        case .nativeRipple: return "Retired: selecting mode 20 in v0.5 stalls USB until the keyboard is reconnected. This image cannot be installed again."
        case .nativeRippleFixed: return "Fixes the mode-20 startup jump that stalled USB in v0.5. Runs a W/A/S/D-triggered rainbow ripple across all 104 keys on the keyboard. Physical animation remains untested. Requires a passing wired USB connection test. Recovery may require hardware access if the keyboard stops responding."
        case .stock: return "Restores the approved stock application from custom v0.2, experimental v0.3/v0.4/v0.5/v0.6 or retired v0.1. The keyboard must still respond over USB."
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview:
            #if GMK104_V08_LOCAL_TEST
            return "Restores the owner-tested v0.7 RAM-only firmware from v0.8. It supports up to sixteen wired on-keyboard layers, but layouts still disappear on power loss. USB must remain responsive for rollback."
            #else
            return "Unreleased local hardware test from v0.6 only. Lighting Studio 1.6.3 can upload up to sixteen supported layers over wired USB; newer Mac-only effects, music and CPU sensor layers are not yet supported. Profiles live in keyboard RAM and disappear on power loss. Persistent Save and Bluetooth/2.4 GHz profile upload are unavailable. Rollback to v0.6 needs working USB."
            #endif
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return "Unreleased read-only flash diagnostic for the verified v0.7 keyboard. It adds a bounded USB query for the flash ID and two proposed 4 KB sectors, but never erases or programs storage. Layers still run from RAM and disappear on power loss. Roll back to v0.7 if USB remains available."
        #endif
        }
    }
    func accepts(source: UInt32) -> Bool {
        if source == Self.auroraLighting.crc && [.custom, .wireless, .streaming].contains(self) { return true }
        switch self {
        case .auroraLighting: return [Self.stock.crc,Self.custom.crc,Self.wireless.crc,Self.streaming.crc,Self.matrixColumns.crc,Self.matrixRainVertical.crc,Self.matrixRainStaggered.crc,Self.matrixRainFixed.crc,Self.matrixLighting.crc,Self.reactiveLighting.crc,Self.performanceLighting.crc,Self.persistentLighting.crc].contains(source)
        case .matrixColumns: return [Self.auroraLighting.crc,Self.persistentLighting.crc, Self.performanceLighting.crc, Self.reactiveLighting.crc, Self.matrixLighting.crc, Self.matrixRainFixed.crc, Self.matrixRainStaggered.crc, Self.matrixRainVertical.crc].contains(source)
        case .matrixRainVertical: return [Self.auroraLighting.crc,Self.matrixColumns.crc,Self.persistentLighting.crc, Self.performanceLighting.crc, Self.reactiveLighting.crc, Self.matrixLighting.crc, Self.matrixRainFixed.crc, Self.matrixRainStaggered.crc].contains(source)
        case .matrixRainStaggered: return [Self.auroraLighting.crc,Self.matrixColumns.crc,Self.matrixRainVertical.crc,Self.persistentLighting.crc, Self.performanceLighting.crc, Self.reactiveLighting.crc, Self.matrixLighting.crc, Self.matrixRainFixed.crc].contains(source)
        case .matrixRainFixed: return [Self.auroraLighting.crc,Self.matrixColumns.crc,Self.matrixRainVertical.crc,Self.matrixRainStaggered.crc,Self.persistentLighting.crc, Self.performanceLighting.crc, Self.reactiveLighting.crc, Self.matrixLighting.crc].contains(source)
        case .matrixLighting: return [Self.auroraLighting.crc,Self.matrixColumns.crc,Self.matrixRainVertical.crc,Self.matrixRainStaggered.crc,Self.persistentLighting.crc, Self.performanceLighting.crc, Self.reactiveLighting.crc, Self.matrixRainFixed.crc].contains(source)
        case .reactiveLighting: return [Self.auroraLighting.crc,Self.matrixColumns.crc,Self.matrixRainVertical.crc,Self.matrixRainStaggered.crc,Self.persistentLighting.crc, Self.performanceLighting.crc, Self.matrixLighting.crc, Self.matrixRainFixed.crc].contains(source)
        case .performanceLighting: return source == Self.auroraLighting.crc || source == Self.persistentLighting.crc || source == Self.reactiveLighting.crc || source == Self.matrixLighting.crc || source == Self.matrixRainFixed.crc || source == Self.matrixRainStaggered.crc || source == Self.matrixRainVertical.crc || source == Self.matrixColumns.crc
        case .persistentLighting: return source == Self.auroraLighting.crc || source == Self.storageDiagnosticRollback.crc || source == Self.performanceLighting.crc || source == Self.reactiveLighting.crc || source == Self.matrixLighting.crc || source == Self.matrixRainFixed.crc || source == Self.matrixRainStaggered.crc || source == Self.matrixRainVertical.crc || source == Self.matrixColumns.crc
        case .storageDiagnosticRollback: return source == Self.persistentLighting.crc
        case .custom: return [Self.stock.crc, Self.wireless.crc, Self.streaming.crc, Self.nativeRipple.crc, Self.nativeRippleFixed.crc].contains(source)
        case .wireless: return [Self.custom.crc, Self.streaming.crc, Self.nativeRipple.crc, Self.nativeRippleFixed.crc].contains(source)
        case .streaming: return source == Self.wireless.crc
        case .nativeRipple: return false
        case .nativeRippleFixed:
            #if GMK104_V07_LOCAL_TEST
            return source == Self.onboardProfilePreview.crc
            #else
            return [Self.wireless.crc, Self.streaming.crc, Self.nativeRipple.crc].contains(source)
            #endif
        case .stock: return [Self.auroraLighting.crc,Self.matrixColumns.crc,Self.matrixRainVertical.crc,Self.matrixRainStaggered.crc,Self.matrixRainFixed.crc, Self.matrixLighting.crc, Self.reactiveLighting.crc, Self.performanceLighting.crc, Self.persistentLighting.crc, Self.storageDiagnosticRollback.crc, 0xD79CC2E1, Self.custom.crc, Self.wireless.crc, Self.streaming.crc, Self.nativeRipple.crc, Self.nativeRippleFixed.crc, 0xC077F2F5].contains(source)
        #if GMK104_V07_LOCAL_TEST
        case .onboardProfilePreview:
            #if GMK104_V08_LOCAL_TEST
            return source == Self.nativeRippleFixed.crc || source == Self.storageSurvey.crc
            #else
            return source == Self.nativeRippleFixed.crc
            #endif
        #endif
        #if GMK104_V08_LOCAL_TEST
        case .storageSurvey: return source == Self.onboardProfilePreview.crc
        #endif
        }
    }
}
struct FirmwarePlan {
    let target: FirmwareTarget
    let start: [UInt8]
    let reports: [[UInt8]]
    let end: [UInt8]
    let imageHash: String
    let streamHash: String
    let paddedHash: String

    init(target: FirmwareTarget, data: Data) throws {
        self.target = target
        let bytes = [UInt8](data)
        imageHash = Self.sha(bytes)
        try require(bytes.count == target.imageSize && imageHash == target.hash, "The bundled \(target.name) image is missing or modified.")
        try require(Self.uint32(bytes, at: 0x18) == UInt32(bytes.count) && Array(bytes[0x20..<0x24]) == Array("KNLT".utf8), "Invalid firmware header.")
        try require(Self.uint32(bytes, at: bytes.count - 4) == target.crc && Self.crc32(Array(bytes.dropLast(4))) == target.crc && Self.crc32(bytes) == 0, "Firmware CRC verification failed.")
        let chunks = (bytes.count + 15) / 16
        let padded = bytes + [UInt8](repeating: 255, count: chunks * 16 - bytes.count)
        paddedHash = Self.sha(padded)
        func packet(_ prefix: [UInt8]) -> [UInt8] { prefix + [UInt8](repeating: 255, count: 64 - prefix.count) }
        start = packet([5, 2, 2, 0, 1, 255])
        var packets: [[UInt8]] = []
        var rebuilt = [UInt8]()
        for first in stride(from: 0, to: chunks, by: 3) {
            let count = min(3, chunks - first)
            var report = packet([5, 2, UInt8(20 * count), 0])
            for slot in 0..<count {
                let index = first + slot
                let crcBytes = [UInt8(truncatingIfNeeded: index), UInt8(index >> 8)] + Array(padded[index * 16..<(index + 1) * 16])
                let crc = Self.crc16(crcBytes)
                let block = crcBytes + [UInt8(truncatingIfNeeded: crc), UInt8(crc >> 8)]
                report.replaceSubrange(4 + slot * 20..<24 + slot * 20, with: block)
                rebuilt += crcBytes.dropFirst(2)
            }
            packets.append(report)
        }
        reports = packets
        let last = UInt16(chunks - 1), inverse = UInt16(0) &- last
        end = packet([5, 2, 6, 0, 2, 255, UInt8(truncatingIfNeeded: last), UInt8(last >> 8), UInt8(truncatingIfNeeded: inverse), UInt8(inverse >> 8)])
        streamHash = Self.sha(start + packets.flatMap { $0 } + end)
        try require(chunks == (target.imageSize + 15) / 16 && packets.count == (target.imageSize + 47) / 48 && Int(last) == chunks-1 && padded.count - bytes.count == 12 && rebuilt == padded,
                    "The OTA packet plan could not reconstruct the approved image.")
        try require(paddedHash == target.paddedHash && streamHash == target.streamHash,
                    "The Mac OTA packet stream differs from the independently verified packet plan.")
    }
    static func sha(_ data: [UInt8]) -> String { SHA256.hash(data: Data(data)).map { String(format: "%02X", $0) }.joined() }
    static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        return crc
    }
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc = UInt16.max
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }
    static func version(_ first: [UInt8], _ second: [UInt8]) throws -> UInt32 {
        try require(first.count == 64 && first == second && Array(first.prefix(4)) == [5, 1, 8, 0], "The keyboard returned inconsistent or malformed firmware identity.")
        try require(uint32(first, at: 4) == 0, "The keyboard firmware version field is not approved.")
        let crc = uint32(first, at: 8)
        try require((FirmwareTarget.allCases.map(\.crc) + [0xC077F2F5, 0xD79CC2E1]).contains(crc), String(format: "Unapproved installed firmware CRC %08X. No flashing is allowed.", crc))
        return crc
    }
    static func intermediateAck(_ response: [UInt8]) throws {
        try require(response.count == 64 && Array(response.prefix(2)) == [5, 2], "Invalid OTA acknowledgment. Transfer stopped; do not retry automatically.")
        try require(Array(response.prefix(6)) != [5, 2, 3, 0, 6, 255], "Unexpected final status during the upload. Transfer stopped.")
    }
    static func finalAck(_ response: [UInt8]) throws -> Bool {
        guard response.count == 64, Array(response.prefix(6)) == [5, 2, 3, 0, 6, 255] else { return false }
        try require(response[6] == 0, "Firmware activation failed with code \(response[6]). Do not retry automatically.")
        return true
    }
}

protocol FirmwareSession: AnyObject {
    func exchange(_ packet: [UInt8], timeout: TimeInterval) throws -> [UInt8]
    func close()
}
struct FirmwareReportPacing {
    private(set) var earliestSend = -Double.infinity
    let afterReply: TimeInterval
    // Keep a full settling interval after every ACK, including delayed replies.
    // 16 ms retains the earlier reference cadence and reduces the time needed
    // for larger images. Late missing ACKs do not prove a device session limit.
    init(exclusive: Bool) { afterReply = exclusive ? 0.016 : 0 }
    mutating func sent(at time: TimeInterval) { earliestSend = time + 0.016 }
    mutating func acknowledged(at time: TimeInterval) {
        earliestSend = max(earliestSend, time + afterReply)
    }
    func delay(at time: TimeInterval) -> TimeInterval { max(0, earliestSend - time) }
}
enum FirmwareConnectionCheck {
    static let replyCount = 4000
    /// Exercise the sustained reply path without sending OTA START, data or END.
    /// This detects connection faults; it does not prove a firmware upload works.
    static func run(session: FirmwareSession, expectedCRC: UInt32,
                    progress: (Double, String) -> Void) throws {
        defer { session.close() }
        let query: [UInt8] = [5, 1] + [UInt8](repeating: 0, count: 62)
        for pair in 0..<(replyCount / 2) {
            let crc = try FirmwarePlan.version(session.exchange(query, timeout: 3), session.exchange(query, timeout: 3))
            try require(crc == expectedCRC, "Firmware identity changed during the read-only connection test.")
            let received = (pair + 1) * 2
            if received % 100 == 0 || received == replyCount {
                let fraction = Double(received) / Double(replyCount)
                progress(fraction, "Testing USB connection • \(Int(fraction * 100))% • no firmware is being written")
            }
        }
    }
}
struct FirmwareTransfer {
    // One minute per upload reply; the separate overall limit remains 12 minutes.
    static let replyTimeout: TimeInterval = 60
    /// Exactly one send per packet. An uncertain START or data write is terminal.
    /// An uncertain END can only be resolved by a fresh post-reboot inspection.
    static func run(_ plan: FirmwarePlan, session: FirmwareSession, sourceCRC: UInt32,
                    progress: (Double, String) -> Void, log: (String) -> Void,
                    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws {
        defer { session.close() }
        let query: [UInt8] = [5, 1] + [UInt8](repeating: 0, count: 62)
        let source = try FirmwarePlan.version(session.exchange(query, timeout: 3), session.exchange(query, timeout: 3))
        try require(source == sourceCRC && plan.target.accepts(source: source), "Installed firmware changed before OTA START. Nothing was flashed.")
        let deadline = clock() + 12 * 60
        log("START SEND")
        try FirmwarePlan.intermediateAck(session.exchange(plan.start, timeout: replyTimeout))
        log("START ACK")
        for (index, report) in plan.reports.enumerated() {
            try require(clock() < deadline, "Transfer deadline exceeded. Do not retry automatically.")
            log("DATA SEND \(index + 1)/\(plan.reports.count)")
            try FirmwarePlan.intermediateAck(session.exchange(report, timeout: replyTimeout))
            log("DATA ACK \(index + 1)/\(plan.reports.count)")
            if index % 25 == 0 || index == plan.reports.count - 1 {
                progress(Double(index + 1) / Double(plan.reports.count) * 0.95, "Uploading firmware • \(index + 1)/\(plan.reports.count) blocks acknowledged")
            }
        }
        try require(clock() < deadline, "Transfer deadline exceeded before activation. Do not retry automatically.")
        log("END SEND")
        let response: [UInt8]?
        do { response = try session.exchange(plan.end, timeout: replyTimeout) }
        catch { response = nil; log("END uncertain: \(error.localizedDescription)") }
        if let response { log(try FirmwarePlan.finalAck(response) ? "END EXACT SUCCESS" : "END UNKNOWN; REBOOT PROOF REQUIRED") }
        progress(0.96, "Waiting for keyboard reboot and firmware verification…")
    }
}
