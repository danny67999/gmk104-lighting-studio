# Troubleshooting

**Play/Save is unavailable:** connect directly by wired USB and use compatible complete firmware. Wireless lighting control does not provide the wired profile-upload interface. Check the Keyboard/device page for the detected capabilities. Buttons remain visible while a check runs; reconnect after any disconnected or uncertain device operation.

**Mac keys do not trigger host effects:** enable Input Monitoring for GMK104 RGB Controller, quit every older app copy and reopen the current copy from Applications. Check the visible key-response status. Firmware playback does not depend on this permission.

**Only WASD lights:** edit that layer's selected keys and Affect all keys setting. Selection controls triggering; Affect all keys controls the output area. Leave it off for a pressed-key-only reactive effect.

**Bluetooth looks slow:** host RGB frames share a limited radio connection. Upload via wired USB and use Play/Save on keyboard for effects that run locally. Keep audio/CPU/Radar layers in host playback as required.

**Wrong version or behavior:** quit other copies and inspect the About/version information. Public release 1.0 groups the newer local apps and complete firmware; it does not mean the old local persistent v1.0. Capabilities and image CRC determine support. Do not install firmware merely to change computer platforms.

**Firmware times out:** keep the keyboard connected, read the installer log and inspect what firmware actually responds. Each exchange waits up to one minute, so an unresponsive operation can take that long to fail. A working typing interface alone does not verify firmware installation. Do not repeat an uncertain flash automatically.

**Profile not restored after unplugging:** use Save to keyboard rather than Play on keyboard or a JSON export. Wait for acknowledgement and full readback, then check the LEDs after power-cycling. Computer restore preferences are separate from persistent firmware storage.
