# Attended v0.8 test sequence

1. Close Lighting Studio. Connect the keyboard by a direct USB data cable in
   wired mode and keep the Mac on power. Confirm ordinary typing and v0.7
   firmware identity.
2. Use the separate local installer to run its read-only 4,000-reply USB
   connection check. Verify the exact v0.8 image CRC `B6EA62D8` and SHA-256
   in `README.md` before requesting an attended firmware update.
3. Only after explicit owner approval for this exact image, install once.
   If upload or postboot verification fails, stop and inspect; never retry
   automatically.
4. Confirm ordinary typing and boot before using `Read storage sectors (no
   changes)`. Record only flash capacity, blank/nonblank status, and SHA-256
   digests, not raw sector contents.
5. Re-test lighting, USB reconnect, Bluetooth, 2.4 GHz, and sleep/wake. If USB
   still responds, the separate installer has the verified v0.7 image for an
   explicitly confirmed rollback.

A read-only survey is not approval to erase/program either proposed sector.
Custom profiles remain RAM-only throughout this test.
