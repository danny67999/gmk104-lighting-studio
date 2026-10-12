# Attended v0.7 RAM-only test plan

**Historical preflight plan.** The owner installed v0.7 and confirmed much
faster onboard effects on September 30; the separate Mac app mismatch was
subsequently fixed. The exact v0.7 image and its hash are recorded in
[STATUS.md](STATUS.md). The separate trial installer must
first pass its offline image and rollback checks. The working v0.6 image must
remain available. Never treat an OTA progress indicator or a sent command as
proof that the new firmware booted.

## Before an approval request

1. Confirm exactly one wired GMK104 RGB interface and a powered Mac. Read the
   currently installed firmware identity and keep the working v0.6 recovery
   image available. Quit other keyboard-control apps before any installer run.
2. Verify the trial installer packages the exact v0.7 SHA-256 and CRC from
   STATUS.md, and that the same installer can select the known v0.6 rollback.
   Check the application name, bundle identifier, and administrative access
   flow without starting an OTA transfer.
3. Ask the owner to approve **this exact image** and the attended test. Explain
   that it has never booted on this keyboard, its live RAM/heap/interrupt-stack
   headroom and rendering time are unmeasured, and a failed boot might need
   physical recovery. Do not reuse an earlier v0.3–v0.6 approval.

## After approval, one staged test

1. Install the pinned v0.7 image once over wired USB. If the reply is missing,
   stop; inspect the live firmware after reconnect instead of retrying blindly.
2. After reboot, confirm **typing first**, then the exact new firmware
   identity, then the existing read-only RGB/sleep interfaces. Select effect
   20 and check the v0.6 rainbow-ripple fallback before sending any profile.
3. Use the Lighting Studio's explicit **Check support** action. Send one simple
   temporary profile: a single static layer or one selected-key ripple, with
   all 104 mappings confirmed. The app must verify every uploaded byte,
   activation completion, and the active profile CRC. Confirm light and typing
   both respond. Start with a simple layer before testing larger stacks.
4. Measure frame timing and key-input responsiveness before trying more
   layers, overlapping pulses, music, temperature, or wireless playback. If
   this cannot be measured reliably, keep the complexity gate in place.
5. Unplug/reconnect to confirm a RAM-only profile disappears and the known
   effect-20 fallback still works. Verify typing again. If anything fails,
   select the pinned v0.6 rollback and verify its boot, typing, and ripple.

This test does **not** validate persistent custom layouts, flash-sector
ownership, Bluetooth or 2.4 GHz profile transfer, sensor streaming over
wireless, built-in-effect profile delegation, or 60/90/120 FPS on the keyboard.
Those require separate firmware and physical tests before a public release.
