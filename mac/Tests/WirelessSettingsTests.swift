import Foundation

@main struct WirelessSettingsTests {
    static func main() throws {
        var frame = [[UInt8]]()
        for start in stride(from: 0, to: 104, by: 9) {
            let count = min(9, 104-start)
            let values: [UInt8] = (start..<(start+count)).flatMap { (index: Int) -> [UInt8] in
                [UInt8(index), UInt8(255-index), UInt8(index/2)]
            }
            frame += try BluetoothPackets.writes(for: [7,3,5,UInt8(start),UInt8(count)] + values)
        }
        var next = 0
        for packet in frame {
            try require(packet.count <= 20 && Int(packet[3]) == next, "Bluetooth fragments must be contiguous and fit ATT MTU 23")
            for index in 0..<Int(packet[4]) {
                try require(Array(packet[(5+index*3)..<(8+index*3)]) == [UInt8(next),UInt8(255-next),UInt8(next/2)], "RGB changed while fragmenting")
                next += 1
            }
        }
        try require(next == 104, "Bluetooth frame did not reach LED 103")
        let unsupported: [[UInt8]] = [[5,2,1,0], [1,0,0,0], [7,3,5,103,2,1,2,3,4,5,6], [7,3,1,5], [7,3,2,19], [8,3,5,104], [7,3,6,1,1,0]]
        for payload in unsupported {
            do { _ = try BluetoothPackets.writes(for: payload); throw NSError(domain: "Accepted unsafe packet", code: 1) }
            catch is ControllerError { }
        }
        let rgbReply = RGBClient.signature + [103,12,34,56,19,4,100,0,0]
        let padded = try BluetoothPackets.reply(rgbReply)
        try require(try RGBClient.parse(padded, index: 103).color == RGB(r:12,g:34,b:56), "Bluetooth reply must retain existing RGB verification")
        try require(try KeyboardSleepState.parse([8,3,6,1] + Array(repeating:0,count:28)) == nil, "Old firmware must not enable sleep writes")
        for seconds in KeyboardPreferences.choices {
            let reply = KeyboardSleepState.signature + [UInt8(seconds&255), UInt8(seconds>>8),3,3,16,14,60,0] + Array(repeating:UInt8(0),count:16)
            try require(try KeyboardSleepState.parse(reply)?.seconds == seconds, "Sleep readback mismatch")
            _ = try BluetoothPackets.writes(for: [7,3,6,1,UInt8(seconds&255),UInt8(seconds>>8)])
        }
        let root = URL(fileURLWithPath: "mac/.build/WirelessSettings-\(UUID())")
        let url = root.appendingPathComponent("keyboard-settings.json")
        try KeyboardPreferences(sleepSeconds: 0).save(to: url)
        try require(try KeyboardPreferences.load(from: url)?.sleepSeconds == 0, "Never must survive relaunch")
        try FileManager.default.removeItem(at: root)
        print("PASS: Bluetooth frame fragmentation, LED 103, command allowlist, v0.2 sleep gate, sleep readback and persistence")
    }
}
