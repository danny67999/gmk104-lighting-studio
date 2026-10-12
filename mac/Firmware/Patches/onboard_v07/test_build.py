"""Offline structural tests; synthetic payload is never written or installed."""
from __future__ import annotations

import hashlib
import struct
import unittest
import zlib

import build


class PackageTests(unittest.TestCase):
    @staticmethod
    def fixture(bss_end: int = build.RAM_BSS_END + 0x1500):
        plan = build.layout()
        # Four C-ABI return stubs exercise image linking only. They implement
        # no upload or rendering behavior and are never persisted to disk.
        ret = bytes.fromhex("67800000")
        payload = ret * 4
        base = plan["payloadBase"]
        entries = dict(zip(("dispatch", "init", "key_down", "render"),
                           (hex(base + i * 4) for i in range(4))))
        manifest = {
            "format": "GMK104-v07-rv32-payload-v1",
            "base": hex(base),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "bssEnd": hex(bss_end),
            "activeFlag": hex(build.RAM_BSS_END),
            "entries": entries,
        }
        return payload, manifest

    def test_source_and_hook_inventory(self):
        info = build.source_layout()
        self.assertEqual(info["hook_base"], 0x20023ED0)
        self.assertEqual(info["free_image_bytes"], 110892)
        self.assertEqual(build.layout()["payloadBase"] % 16, 0)
        self.assertEqual(info["old_targets"], build.EXPECTED)

    def test_packaged_candidate_changes_only_listed_sites(self):
        payload, manifest = self.fixture()
        image, details = build.build(payload, manifest)
        original = build.source_layout()["image"]
        self.assertLess(len(image), build.MAX_IMAGE)
        self.assertEqual(zlib.crc32(image) ^ 0xffffffff, 0)
        self.assertEqual(struct.unpack_from("<I", image, 0x18)[0], len(image))
        self.assertEqual(image[build.layout()["payloadBase"] - build.BASE:
                               build.layout()["payloadBase"] - build.BASE + len(payload)], payload)
        changed = {i for i, (old, new) in enumerate(zip(original[:-4], image)) if old != new}
        allowed = set(range(0x18, 0x1C))
        for patch in details["patches"]:
            at = int(patch["offset"], 16)
            allowed.update(range(at, at + 4))
        self.assertEqual(changed, changed & allowed)
        self.assertEqual(len(details["patches"]), 6)
        self.assertEqual(details["status"], "offline-candidate-only")

    def test_bss_growth_keeps_trampoline_layout_fixed(self):
        payload, manifest = self.fixture()
        first, _ = build.build(payload, manifest)
        manifest["bssEnd"] = hex(build.MAX_BSS_END)
        second, _ = build.build(payload, manifest)
        self.assertEqual(len(first), len(second))
        self.assertEqual(build.layout()["payloadBase"],
                         build.BASE + first.find(payload))

    def test_rejects_unlinked_or_out_of_bounds_payload(self):
        payload, manifest = self.fixture()
        bad = dict(manifest, sha256="0" * 64)
        with self.assertRaises(AssertionError):
            build.build(payload, bad)
        bad = dict(manifest, base=hex(int(manifest["base"], 0) + 16))
        with self.assertRaises(AssertionError):
            build.build(payload, bad)
        bad = dict(manifest, bssEnd=hex(build.MAX_BSS_END + 1))
        with self.assertRaises(AssertionError):
            build.build(payload, bad)
        bad = dict(manifest, activeFlag=hex(build.RAM_BSS_END - 1))
        with self.assertRaises(AssertionError):
            build.build(payload, bad)
        bad = dict(manifest, entries=dict(manifest["entries"], render=hex(build.BASE)))
        with self.assertRaises(AssertionError):
            build.build(payload, bad)


if __name__ == "__main__":
    unittest.main()
