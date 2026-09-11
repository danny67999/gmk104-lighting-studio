# GMK104 Lighting Studio for macOS

A native RGB lighting app for the ZUOYA GMK104, with layered effects, system-audio response, CPU temperature colors, USB and 2.4 GHz control, and a companion firmware installer. Bluetooth lighting and adjustable wireless sleep are experimental additions requiring firmware v0.3.

**[Download the Mac apps](https://github.com/danny67999/gmk104-lighting-studio/releases/latest)**

[Wireless beta 1.5](https://github.com/danny67999/gmk104-lighting-studio/releases/tag/v1.5.0-beta.1) contains the updated controller app. The experimental v0.3 firmware is local only and is not included in the public download. The latest stable release remains available above.

Apple Silicon • macOS 13+ • Adaptive music requires macOS 14.2+

## Install

1. Download the release disk image and drag **GMK104 RGB Controller** and **GMK104 Firmware Installer** into Applications.
2. Open the controller and connect one GMK104 over wired USB, or plug in its dongle and select 2.4 GHz mode.
3. The controller requires custom firmware v0.2. If it reports stock firmware, quit the controller and open the firmware installer. Inspect the keyboard before choosing an update.
4. Enable **Input Monitoring** for GMK104 RGB Controller in System Settings → Privacy & Security, then click **Enable key response**. The button turns green only after the keyboard listener starts.
5. Add effects with **Add layer**, then click **Apply & save layers**.

These community builds are ad-hoc signed and are not Apple-notarized. On a first download, macOS may require **System Settings → Privacy & Security → Open Anyway**. Only open a download you trust. The app needs neither a driver installation nor an administrator helper.

If key response stops after an update, check the Input Monitoring status inside the app. macOS can retain an entry for an earlier ad-hoc build. Remove that entry and add the current app from Applications, relaunch it, then enable key response. The button turns green only after the selected keyboard's listener opens successfully.

## Effects and layers

Combine up to 16 layers, with independent effect, speed, intensity, opacity, blend mode, trigger keys and output coverage. The top layer appears above those below. **Normal** blends a layer over the background; **Add light** adds its color. Changes take effect when you apply and save.

| Effect | Behavior |
| --- | --- |
| Ripple | A ring expands from each pressed key. |
| Rainbow ripple | A rotating rainbow ring expands from each pressed key and mixes with other ripples. |
| Reactive | Pressed keys light up and fade. |
| Rainbow wave | A rainbow moves across the keyboard. |
| Breathing | The selected color brightens and dims. |
| Spectrum cycle | Colors cycle across the layer. |
| Static color | A steady background or highlight. |
| Adaptive music | Bass, mids and treble animate the keyboard from audio playing on the Mac. |
| CPU temperature | The hottest readable CPU sensor sets a blue → green → red color. |

**Affect all keys** controls where each layer renders. For example, select WASD as a Rainbow ripple layer's triggers and turn on Affect all keys: only WASD starts ripples, but their light travels across all 104 mapped keys. Turning it off confines the light to WASD. An empty key selection disables the layer's output.

### Animation frame rate

Choose **Animation FPS cap** (15, 30, 60, 90 or 120), then **Apply & save layers**. The default is 60. The live header shows achieved FPS alongside the applied cap. The cap is shared by the layer stack because the keyboard receives one combined frame. It changes frame pacing without changing the ripple's travel speed or duration. USB speed and readback verification may keep actual FPS below the selected cap. No USB safety checks are removed to chase a higher rate.

Version 1.4 keeps ripple rings visible until they pass the farthest mapped key. Rainbow color cycling wraps independently of travel distance, so reaching the last hue cannot end the ripple. Speed controls travel time.

### Adaptive music

Add an Adaptive music layer and apply it. Allow **System Audio Recording** when macOS asks. The layer shows its capture status and a live audio meter. **Retry audio** restarts capture after a permission or audio-device change. Adjust sensitivity per layer; gain also adapts to playback volume automatically. Silence fades the layer away, exposing the layers below.

The app uses a private [Core Audio process tap](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), with unmuted playback. It does not use the microphone, save sound, or send audio to a server. Multiple music layers share one capture source. Capture stops when no applied, visible music layer needs it, when playback stops, or when the keyboard disconnects. Some protected audio sources may not permit capture.

### CPU temperature

Add a CPU temperature layer and apply it. The live label reports Celsius and the number of readable sensors. Set the blue and red endpoints independently for that layer (defaults: 40°C and 90°C). Green is halfway between them. These are lighting preferences, not hardware safety limits.

Temperature comes from read-only AppleSMC CPU sensor values, not CPU utilization or macOS thermal-pressure estimates. Unavailable, invalid or stale readings leave the layer transparent and show an unavailable message. AppleSMC is an undocumented interface; sensor availability can change between Macs and macOS versions. Verified on an Apple M5 running macOS 27. No fan speeds, voltages or power settings are changed. See [technical references](THIRD_PARTY_NOTICES.md).

## Bluetooth and 2.4 GHz

**2.4 GHz:** plug in the GMK104 receiver (`320F:5088`) and select 2.4 GHz mode. The exact `FF60:0061` interface forwards the existing v0.2 RGB protocol. A complete 104-LED frame was written and read back through this receiver. Key response still requires Input Monitoring for the installed app. The listener observes only keyboard interfaces belonging to that receiver's USB attachment. A wired GMK104 takes priority when its cable is connected.

When the keyboard sleeps, the receiver remains plugged in but stops answering RGB queries. The app pauses, keeps the saved profile and checks for a reply every five seconds. Press a physical key to wake the keyboard. Manual Disconnect stops automatic retries.

**Bluetooth (experimental app support):** v0.2 has no Bluetooth RGB service. The controller now includes a separate encrypted GATT transport, paired PnP identity checks, acknowledged writes, RGB readback and exact keyboard input selection for a proposed v0.3 firmware service. The v0.3 firmware is local only and is not included in this public beta. Bluetooth lighting has not been tested on hardware and remains unavailable with public v0.2 firmware. The existing public installer cannot install v0.3.

**Wireless sleep after:** choose 1, 2, 5, 10, 15, 30 or 60 minutes, or Never, then Apply sleep time. This changes the firmware's idle threshold for Bluetooth and 2.4 GHz and verifies it by reading it back. Controls remain locked on v0.2. The setting is saved separately on this Mac and reapplied after reconnect; powering off the keyboard resets its local setting to the five-minute default until the app reconnects. Never may use more battery. It does not disable low-battery protection or the Mac's own sleep settings.

**All firmware updates require wired USB.** The installer excludes the receiver and Bluetooth from its flashing path.

## Mapping and reconnection

The included 104-key map starts with **Escape at LED 0**, runs across each row, then moves to the next. Key mapping has a Back button and an undoable reset. Click a physical key on the diagram or press it to test its LED. This does not alter its assignment.

If a key differs, use the advanced manual mapping controls: choose/light an LED, select its key, then save. Quick mapping captures a physical key and advances to the next LED. Assignments happen only while the mapping window is active. The row-layout preset can be reapplied with a backup and Undo.

Mappings and lighting profiles are saved locally in `~/Library/Application Support/GMK104RgbController/`. A saved profile resumes after reconnect or relaunch when **Restore saved lighting after reconnect** is enabled. Stop saves a paused state. USB identity is checked before restoration. Closing the window keeps lighting running in the menu bar; quitting the app stops the host animations. Existing profiles and maps survive upgrades.

## Firmware installer

The public companion installer packages the exact custom v0.2 image built and flashed on Windows, plus the stock rollback image. It opens with offline hash and packet checks, then offers read-only **Inspect keyboard**. Already-installed firmware requires no update. A real update requires a readiness checkbox and the exact displayed confirmation phrase.

Use a stable wired USB connection and Mac power. Custom firmware is experimental. Keep the app open and the cable connected during upload and reboot. Stock rollback works only while the keyboard's OTA and RGB interfaces still respond; it is not a USB-dead recovery bootloader. See [the firmware guide](mac/Firmware/README.md) for approved transitions, checks and verification limits.

## Build and test

Install Xcode or current Apple Command Line Tools. From the repository root:

```sh
./mac/test.sh
./mac/build.sh
./mac/Firmware/build.sh
./mac/package.sh
```

The app bundles and disk image appear in `outputs/`. The build targets Apple Silicon. No third-party package manager or network dependency is needed. A current SDK with Core Audio process-tap declarations is required to compile; the runtime checks macOS 14.2 availability.

The tests use mock USB and isolated profiles. They cover exact firmware identity, complete RGB readback, checksums, status lights, mapping, layers, persistence, reconnects, stale callbacks, full-keyboard ripple travel, audio signal analysis, temperature colors, firmware image hashes and exact OTA stream equivalence, and interrupted transfers without retries.

## USB verification

USB RGB control accepts wired `320F:5055` or receiver `320F:5088`, exact RGB usage `FF60:0061`, the custom v0.2-compatible signature and the current attachment. Bluetooth uses a separate identity and service gate. Each lighting start verifies all 104 LEDs, the checksum and stable readback. Animation sends complete frames through one serialized writer, validates samples and checksums, and performs periodic complete audits. Obsolete frames are dropped rather than queued.

Firmware v0.2 can force status-light slots 14, 33, 57 and 91 to white. Only those exact white overrides are accepted; other mismatches stop playback. Transport or attachment failures close the connection. A color-verification failure retains the connection only if that same keyboard and firmware still verify.

The public release includes automated verification and native Mac checks. Physical LED labeling, RF modes, long-term firmware stability and USB-dead recovery remain device-specific checks. The Mac installer has been validated offline and by live read-only inspection; a real Mac flash has not been performed because the connected keyboard already has the target firmware.

## Beta verification

Controller 1.5.0 passed local automated tests, native compilation and bundle verification. A complete 104-LED RGB frame was written and read back through the 2.4 GHz receiver, then the original built-in effect was restored. Bluetooth discovery confirmed that v0.2 has no RGB service. Bluetooth and sleep UI/protocol tests pass, but those features need firmware that is not part of this public beta and have not been tested physically. Physical 2.4 GHz key-response confirmation is pending Input Monitoring authorization for the updated build.
