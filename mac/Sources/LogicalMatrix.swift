import Foundation

/// Fixed logical columns follow key IDs, including wide and staggered keys.
enum LogicalMatrixRaster {
    static let assignments: [String: UInt8] = ["Escape":0,"Backquote":32,"Digit1":32,"Tab":64,"CapsLock":96,"ShiftLeft":128,"ControlLeft":160,"F1":1,"Digit2":33,"KeyQ":65,"KeyA":97,"KeyZ":129,"AltLeft":161,"MetaLeft":161,"F2":2,"Digit3":34,"KeyW":66,"KeyS":98,"KeyX":130,"Space":162,"F3":3,"Digit4":35,"KeyE":67,"KeyD":99,"KeyC":131,"F4":4,"Digit5":36,"KeyR":68,"KeyF":100,"KeyV":132,"F5":5,"Digit6":37,"KeyT":69,"KeyG":101,"KeyB":133,"F6":6,"Digit7":38,"KeyY":70,"KeyH":102,"KeyN":134,"F7":7,"Digit8":39,"KeyU":71,"KeyJ":103,"KeyM":135,"F8":8,"Digit9":40,"KeyI":72,"KeyK":104,"Comma":136,"F9":9,"Digit0":41,"KeyO":73,"KeyL":105,"Period":137,"F10":10,"Minus":42,"KeyP":74,"Semicolon":106,"Slash":138,"AltRight":170,"F11":11,"Equal":43,"BracketLeft":75,"Quote":107,"ShiftRight":139,"MetaRight":171,"F12":12,"Backspace":44,"BracketRight":76,"Enter":108,"ContextMenu":172,"Backslash":77,"ControlRight":173,"PrintScreen":14,"Insert":46,"Delete":78,"ArrowLeft":174,"ScrollLock":15,"Home":47,"End":79,"ArrowUp":143,"ArrowDown":175,"Pause":16,"PageUp":48,"PageDown":80,"ArrowRight":176,"NumLock":49,"Numpad7":81,"Numpad4":113,"Numpad1":145,"Numpad0":177,"NumpadDivide":50,"Numpad8":82,"Numpad5":114,"Numpad2":146,"NumpadMultiply":51,"Numpad9":83,"Numpad6":115,"Numpad3":147,"NumpadDecimal":179,"NumpadSubtract":52,"NumpadAdd":116,"NumpadEnter":180]
    static func automatic(keyID: String, time: Double, settings: LightingSettings) -> RGB {
        guard let packed = assignments[keyID], (packed & 31) % 2 == 0 else { return .black }
        return MatrixRainRaster.pixel(x: Int(packed & 31) * 2, y: Int(packed >> 5) * 2,
                                      minY: 0, maxY: 10, time: time, settings: settings)
    }
    private static func milliseconds(_ time: Double) -> UInt32 {
        guard time.isFinite else { return 0 }
        var ms = (time.truncatingRemainder(dividingBy: 4294967.296) * 1000).rounded(.down)
        if ms < 0 { ms += 4294967296 }
        return UInt32(ms)
    }
    private static func mul(_ a: Int, _ b: Int) -> Int { (a * b + 127) / 255 }
    static func reactive(keyID: String, time: Double, pulses: [KeyPulse], settings: LightingSettings) -> RGB {
        guard let packed = assignments[keyID] else { return .black }
        let column = packed & 31, row = Int(packed >> 5), now = milliseconds(time)
        let speed = Int((settings.speed * 256).rounded()), intensity = Int((settings.intensity * 255).rounded())
        var result = RGB.black
        for pulse in pulses {
            guard let origin = assignments[pulse.keyID], origin & 31 == column else { continue }
            let elapsed = now &- milliseconds(pulse.time)
            guard elapsed < 18000 else { continue }
            let age = Int(elapsed) * speed / 1000
            guard age < 1152 else { continue }
            let distance = age * 1280 / 9 - row * 65536 / 6
            guard (0..<49152).contains(distance) else { continue }
            let white: Int, glow: Int
            if distance < 8192 { white = 255 - distance * 255 / 8192; glow = 255 - distance * 32 / 8192 }
            else { white = 0; glow = 220 * (49152 - distance) / 40960 }
            let coverage = mul(glow, intensity)
            func channel(_ value: UInt8) -> UInt8 { UInt8(mul(Int(value) + mul(255 - Int(value), white), coverage)) }
            result = RGB(r: max(result.r, channel(settings.color.r)), g: max(result.g, channel(settings.color.g)), b: max(result.b, channel(settings.color.b)))
        }
        return result
    }
}
