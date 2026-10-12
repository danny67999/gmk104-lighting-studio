# Latest complete image v1.7 — spaced Matrix and key rain

`build_matrix_v17.sh` adds effectIDs25/26, retains all earlier effects and16layers, and uses the same guarded two-slot profile journal. Logical scan-to-column/row membership is cached in104bytes at activation;rendering uses direct indexed lookup. Columns follow the explicit104key groups rather than geometric centers. Continuous odd columns are active/even dark;reactive trails start at their column top and expire below the bottom. Independent triggers/output masks and effect speed are preserved.

Complete image174,164bytes,CRC193BCBFA,SHA-2564B1FF3A4760FCE95E4C75B24D2622B3389603614AC8AB4642897CD6FFC35D4C0. Text/rodata25,916bytes;data0;BSS11,948bytes;end0x957DC,beneath the provisional0x96000cap. Cooperative rendering still processes2LEDs,4ripple distances and1input event per visit and publishes only completed frames. Offline1/16layer parity,120C/Mac/Windowsframe parity,all21reactivecolumns and5,675interruption boundaries passed. Compiled instruction peak1,650forautomaticspacing and3,134for16recentpresses in one column,including16layers;these are emulator results,not physical latency measurements. No firmware was flashed;target boot/timing/radio and power-cycle tests remain pending. Frozenv1.6rebuilds byte-for-byte.

# Full persistent-lighting firmware integration

The builder produces `GMK104-persistent-lighting-v1.0.bin`, a full feature image extending the pinned v0.6 application. It integrates all Studio/manual renderer effects 0–17, sixteen layers, per-key geometry and remapping, independent speeds, key press/release, guarded journal storage and automatic boot restoration with saved brightness. No build/test script opens hardware or sends a write.

The exact current image is 167,252 bytes, CRC `D51110C3`, SHA-256 `3980487576adeb2a682c205309e523bee7d42030d6525eff368fe7296aba2da8`. Source firmware and stock flash routines/startup epilogue are pinned. Only the seven listed hook sites, image size and CRC are modified in the existing application. The appended payload uses 19,008 bytes of code/rodata and 11,340 BSS bytes; its BSS ends at `0x9557C`, below the provisional `0x96000` limit. There is no initialized RAM data, heap or unresolved linker symbol. Physical heap/ISR bounds and timing still require target validation.

## Guarded allocation decision

This replaces the earlier all-or-nothing requirement for an unavailable complete vendor flash map with a narrow, fail-closed runtime allocation. It is a reverse-engineered allocation, not proof of every ROM behavior.

The existing v0.8 survey directly established JEDEC `0x00146085`, 1 MB capacity and erased `0x8C000`/`0x8D000`. The exact GMK104 stock application initializes OTA bases `0`/`0x40000`, stores settings within `0x82000`–`0x8B000`, and initializes BLE storage at `0xFC000`. [Telink's B91 SDK flash documentation](https://doc.telink-semi.cn/doc/en/software/res/sdk/ble/b91_ble_single_connection_en/b91_ble_single_connection_en/#mcu-address-space) reserves default OTA banks through `0x7FFFF`, BLE pairing at `0xFC000`/`0xFD000`, calibration at `0xFE000` and identity at `0xFF000`; other storage is application data. This supports the proposed allocation but does not prove the GMK104 vendor never generates another address.

Accordingly, the hardware adapter requires the exact surveyed chip, checks both live OTA-base pointers remain in `0`/`0x40000`, checks the BLE base remains `0xFC000`, and validates both BLE sector pointers and every dynamically populated pairing-record pointer against `0xFC000`–`0xFDFFF`. These checks run again during journal I/O. Physical erase/program also requires current wired USB mode. If any guard fails, persistent capability is disabled while RAM playback remains available.

Preparation reads both sectors and accepts only blank contents, an exact 32-byte allocation marker at offset 3968, or a compatible interrupted marker with every other byte erased. Unknown data is never erased. The erase callback verifies the complete erase, writes and reads back the allocation marker, and only then permits profile payload. The ownership marker lies beyond the maximum 2536-byte v1 profile and before the existing journal tail at 4064. An interrupted erase may make the inactive sector unrecognizable: new saves then remain disabled, but the other owned, validated generation can still restore without repair writes.

The normal Mac installer independently performs the bounded v0.8 read before OTA START. It pins image, padded image and packet-stream hashes and bundles the exact v0.8 rollback. Its default target is Persistent lighting v1.0. It never treats an offline pass or postboot identity as a power-cycle success.

## Offline checks

```sh
sh mac/Firmware/Patches/onboard_persistent/test.sh
sh mac/Firmware/Patches/onboard_persistent/build_offline.sh \
  /private/tmp/xpack-riscv-none-elf-gcc-15.2.0-1 \
  /private/tmp/gmk104-persistent-image
bash mac/test.sh
bash mac/Firmware/build.sh
```

The guarded NOR simulator covers 5,675 interruption boundaries, including an erase that removes the reservation marker before the old payload. It restores either the old or newly committed profile without boot writes. Other tests cover unknown inactive-sector data, read/layout failures, sixteen-layer exact-byte restoration, saved brightness and actual adapter key release. Four package and four instruction-level tests verify the integrated scan/startup hooks and allowed image changes. The shared renderer/journal tests and normal Mac transfer/helper checks also pass.

The built file still needs explicit exact-image approval, physical installation, persistent-profile-save approval and target validation. Nothing has been flashed or committed by the build. Profile transfers are wired only; onboard playback across Bluetooth/2.4 GHz requires target checks. Music/temperature need host samples. The stock scheduler imposes a 50 FPS ceiling.
