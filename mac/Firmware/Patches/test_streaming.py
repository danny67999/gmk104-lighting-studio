"""Check v0.4's exact one-byte change and the existing Write Command handler."""
import struct
from pathlib import Path
from build_streaming import build
import test_wireless as original

image, manifest = build()
root = Path(__file__).resolve().parents[1]
assert image == (root / 'Resources/GMK104-custom-RGB-v0.4-experimental.bin').read_bytes()
source = (root / 'Resources/GMK104-custom-RGB-v0.3-experimental.bin').read_bytes()
offset = int(manifest['propertyOffset'], 16)
assert [(i,a,b) for i,(a,b) in enumerate(zip(source[:-4],image[:-4])) if a != b] == [(offset,10,14)]
assert manifest['crc'] == '6F0AD0C1' and manifest['dataReports'] == 2976
table = int(original.MANIFEST['tableOffset'],16)
assert source[table:table+71*24] == image[table:table+71*24]
assert struct.unpack_from('<HBBIIIII', image, table+70*24)[1] == 0x23
original.IMAGE = image
for seed in range(20):
    colors = bytes((i*19 + seed*7) % 256 for i in range(312))
    machine = original.Machine()
    for start in range(0,104,5):
        count = min(5,104-start)
        machine.ble([7,3,5,start,count]+list(colors[start*3:(start+count)*3]),opcode=0x52)
        assert machine.r[10] == 0
    # An acknowledged query after the burst must see every final color and sum.
    for index in range(104):
        result = machine.ble([8,3,5,index],opcode=0x12)
        assert result[12:15] == colors[index*3:index*3+3]
        assert int.from_bytes(result[17:19],'little') == sum(colors)%65536
for payload in ([5,2,1,0], [7,3,5,103,2,1,2,3,4,5,6], [7,3,5,0,6]+[1]*18, [7,3,5,0,1,1,2], [7,3,1,5]):
    machine = original.Machine(); machine.ble(payload,opcode=0x52)
    assert machine.r[10] == 0x0d and not machine.writes
for mode in (1,2):
    machine = original.Machine(); machine.ble([7,3,5,0,1,1,2,3],opcode=0x52,mode=mode)
    assert machine.r[10] == 0x0d and not machine.writes
print('PASS: v0.4 changes only one property byte plus CRC; executable code, ATT permissions and prior handles are unchanged')
print('PASS: 20 complete unacknowledged RGB frames read back at all 104 LEDs with matching checksums; malformed packets and non-Bluetooth modes are rejected')
print('Offline instruction tests only: radio throughput, boot and host backpressure still require a physical test.')
