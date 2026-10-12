# v0.8 storage test status

## Current verified state: 2026-10-01

The owner corrected the stale installation status. Fresh live wired inspection
now confirms v0.8 CRC `B6EA62D8` on the keyboard. The bounded read-only storage
survey succeeded using the existing GET command, without another firmware
installation or any storage erase/program/profile commit.

- Live JEDEC ID: `0x00146085`; reported capacity: 1 MB.
- Proposed sector `0x8C000`: all 4,096 bytes are `0xFF`.
- Proposed sector `0x8D000`: all 4,096 bytes are `0xFF`.
- Both sector SHA-256 values:
  `F47A8EC3E9AFF2318D896942282AD4FE37D6391C82914F54A5DA8A37DE1300C6`.

This establishes capacity and current candidate contents. Blank sectors alone
do not establish ownership; stock/ROM generated addresses and normal settings
writes still require verification before the sectors become a permanent-save
allocation. This survey is not a full physical flash dump, and no permanent
profile was written. Typing, wireless and sleep behavior were not tested in
this read-only session.

The existing v0.8 image was packaged for direct access. It is byte-identical
to the firmware in the earlier storage-test installer. No rebuilt v0.8 image
was used. The complete-profile runtime remains separate source/ELF work.

## Earlier snapshot (superseded installation status)

As of the 2026-09-30 snapshot, the read-only diagnostic firmware and separate local
installer are built and pass offline image, transfer, helper-authorization,
RV32 hook, sanitized device-handler, and storage-response tests. The image is
described there as **not installed**. That snapshot missed the subsequent
owner installation and must not be used to report the current firmware.

The old next-step instruction to install v0.8 is also superseded: no reinstall
is needed for the current read command. Persistent flash writes remain disabled
until allocation/ownership, hardware binding and recovery are established.
