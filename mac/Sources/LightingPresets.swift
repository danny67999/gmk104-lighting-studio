import Foundation

enum LightingPreset: String, CaseIterable, Identifiable {
    case matrixTerminal = "Matrix Terminal"
    case arcticRipple = "Arctic Ripple"
    case emberGlow = "Ember Glow"
    case synthwave = "Synthwave"
    case rainbowParty = "Rainbow Party"
    var id: String { rawValue }
    var detail: String {
        switch self {
        case .matrixTerminal: return "Spaced green rain with falling trails when you type."
        case .arcticRipple: return "Icy ripples over a dim navy background."
        case .emberGlow: return "Soft fire with orange flashes on pressed keys."
        case .synthwave: return "Cyan WASD, pink waves on key presses, and a purple glow."
        case .rainbowParty: return "Rainbow ripples over a subtle moving rainbow."
        }
    }
    func layers() -> [LightingLayer] {
        func layer(_ name:String,_ effect:LightingEffect,_ color:RGB = .black,_ intensity:Double = 1,_ speed:Double = 1,
                   _ keys:[String]? = nil,_ reach:Bool = false,_ blend:LayerBlendMode = .normal) -> LightingLayer {
            var value = LightingLayer(name:name,settings:LightingSettings(effect:effect,color:color,speed:speed,intensity:intensity))
            value.keyIDs=keys;value.affectAllKeys=reach;value.blendMode=blend;return value
        }
        switch self {
        case .matrixTerminal:
            return [layer("Key rain",.matrixKeyRain,RGB(r:30,g:255,b:70),1,1,nil,true,.additive),
                    layer("Spaced rain",.spacedMatrixRain,RGB(r:0,g:255,b:32),0.6,0.7)]
        case .arcticRipple:
            return [layer("Ice ripple",.ripple,RGB(r:100,g:220,b:255),1,0.8,nil,true,.additive),
                    layer("Navy base",.staticColor,RGB(r:0,g:8,b:25))]
        case .emberGlow:
            return [layer("Ember key flash",.reactive,RGB(r:255,g:150,b:25),1,1,nil,false,.additive),
                    layer("Soft fire",.fire,.black,0.22,0.6)]
        case .synthwave:
            return [layer("Cyan WASD",.staticColor,RGB(r:0,g:220,b:210),0.8,1,["KeyW","KeyA","KeyS","KeyD"]),
                    layer("Pink key waves",.rowWave,RGB(r:255,g:25,b:170),0.8,1,nil,true,.additive),
                    layer("Purple breathing",.breathing,RGB(r:85,g:0,b:160),0.25,0.5)]
        case .rainbowParty:
            return [layer("Rainbow key ripple",.rainbowRipple,.black,1,1,nil,true,.additive),
                    layer("Soft rainbow wave",.wave,.black,0.16,0.5)]
        }
    }
}
