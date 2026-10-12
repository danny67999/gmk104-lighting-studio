"""Offline release allowlist validation. Does not access any hardware."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalog = json.loads((root / 'firmware-catalog.json').read_text())
expected = {entry['file']: entry['sha256'].lower() for entry in catalog['firmware']}
assert len(expected) == 5 and catalog['release'] == '1.0'
for folder in ('mac/Firmware/Resources', 'windows/Firmware'):
    for name, digest in expected.items():
        assert hashlib.sha256((root / folder / name).read_bytes()).hexdigest() == digest, (folder, name)
assert {p.name for p in (root / 'windows/Firmware').glob('*.bin')} == set(expected)
mac_build = (root / 'mac/Firmware/build.sh').read_text()
names = re.search(r'for image in (.+); do', mac_build).group(1).split()
assert set(names) == set(expected) and len(names) == 5
plan = (root / 'mac/Firmware/Sources/FirmwarePlan.swift').read_text()
assert re.search(r'publishedCases.*\[\.auroraLighting, \.custom, \.wireless, \.streaming, \.stock\]', plan)
windows = (root / 'windows/Installer/FirmwareLauncher.cs').read_text()
assert re.findall(r'"(GMK104[^"\n]+\.bin)"', windows) == list(expected)
flasher = (root / 'windows/Firmware/GMK104-Guarded-Flasher.ps1').read_text()
assert "[ValidateSet('Release','Custom','Wireless','Streaming','Stock')]" in flasher
assert flasher.count('Exchange($plan.Start,60000') == 1
assert flasher.count('Exchange($plan.DataReports[$i],60000') == 1
assert flasher.count('Exchange($plan.End,60000') == 1
print('PASS: both installers select the five published firmware images; hashes and one-minute exchange waits match')
