import Foundation

@main struct MatrixRainTests {
    static func main() throws {
        let keys = try JSONDecoder().decode([KeyGeometry].self, from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/layout.json")))
        let map = try JSONDecoder().decode(MappingFile.self, from: Data(contentsOf: URL(fileURLWithPath: "mac/Resources/default-led-map.json")))
        let reference = [UInt8](try Data(contentsOf: URL(fileURLWithPath: "mac/Tests/Fixtures/matrix-native-frames-v1.6.bin")))
        let settings = LightingSettings(effect: .matrixRain, color: RGB(r: 0, g: 255, b: 32))
        func frame(_ t: Double,_ s: LightingSettings = settings) -> [RGB] {
            LightingRenderer.frame(settings:s, keys:keys, mapping:map, pulses:[],time:t)
        }
        assert(reference.count == 60 * 312)
        for i in 0..<60 {
            assert(frame(Double(i)/10).flatMap(\.bytes) == Array(reference[(i*312)..<((i+1)*312)]), "Mac preview and native Matrix rain must match byte for byte")
        }
        let first=frame(0)
        for key in keys {
            let index=map.mappings.first{$0.keyId==key.id}!.ledIndex!
            if first[index] != .black { assert(key.y == 0, "Entering heads cannot spawn below the top row") }
        }
        assert(frame(1) != frame(2) && !settings.effect.requiresKeyPresses && settings.effect.hasAdjustableSpeed)
        var fast=settings;fast.speed=2;assert(frame(1.3)==frame(0.65,fast))
        var dim=settings;dim.intensity=0;assert(frame(1,dim).allSatisfy{$0 == .black})
        var red=settings;red.color=RGB(r:255,g:0,b:0);assert(frame(1,red) != frame(1))
        var top=LightingLayer(settings:settings);top.keyIDs=["KeyW"];top.affectAllKeys=false
        let selected=LayerRenderer.frame(layers:[top],keys:keys,mapping:map,pulses:[],time:1)
        let w=map.mappings.first{$0.keyId=="KeyW"}!.ledIndex!
        assert(selected.enumerated().allSatisfy{$0.offset==w || $0.element == .black})
        top.affectAllKeys=true
        assert(LayerRenderer.frame(layers:[top],keys:keys,mapping:map,pulses:[],time:1)==frame(1))
        let caps=[UInt8](try Data(contentsOf:URL(fileURLWithPath:"mac/Tests/Fixtures/onboard-capabilities-v1.3.bin")))
        assert(caps.count==32 && caps[20]==24)
        var sameColumn=0, headSteps=0, wraps=0, tails=0, whites=0, staggered=0, previousHead: Int?, entered=false
        for tick in 0..<1600 {
            let t=Double(tick)/100
            let column=(0..<6).map { MatrixRainRaster.pixel(x:8,y:1+$0*2,minY:1,maxY:11,time:t,settings:settings) }
            for row in 0..<6 {
                assert(column[row]==MatrixRainRaster.pixel(x:9,y:1+row*2,minY:1,maxY:11,time:t,settings:settings))
                sameColumn+=1
                if column[row].r>0 && column[row].g>=223 { whites+=1 }
            }
            let lit=column.filter{$0 != .black}.count
            let head=column.indices.max { column[$0].g < column[$1].g }!
            if lit>0 {
                if !entered { assert(head==0 && lit==1);entered=true }
                if let previousHead,head != previousHead {
                    if head==0 {assert(previousHead==5);wraps+=1} else {assert(head==previousHead+1);headSteps+=1}
                }
                previousHead=head
            }
            if tick>=500 {
                assert((4...5).contains(lit))
                let transitions=(0..<6).filter { (column[$0] == .black) != (column[($0+1)%6] == .black) }.count
                assert(transitions==2, "Reference has a continuous tail and a moving dark space")
                for age in 1..<4 {assert(column[(head+6-age+1)%6].g>=column[(head+6-age)%6].g)}
                tails+=1
            }
            for row in 1..<5 {
                let neighbor=MatrixRainRaster.pixel(x:10,y:1+row*2,minY:1,maxY:11,time:t,settings:settings)
                if (column[row] == .black) != (neighbor == .black) {staggered+=1}
            }
        }
        assert(entered && headSteps>30 && wraps>=6 && tails==1100 && whites>200 && staggered>100 && sameColumn==9600)
        for x in 0..<24 {
            var started=false
            for tick in 0..<200 where !started {
                let column=(0..<6).map {MatrixRainRaster.pixel(x:x*2,y:1+$0*2,minY:1,maxY:11,time:Double(tick)/100,settings:settings)}
                if column.contains(where:{$0 != .black}) {assert(column[0].g>=223 && column.dropFirst().allSatisfy{$0 == .black});started=true}
            }
            assert(started)
        }
        print("PASS: transposed reference has white downward heads, continuous fading tails, moving dark spaces, staggered starts and seamless wrapping")
        print("PASS: Matrix rain animates without presses, matches 60 production-native frames, scales speed, honors color/intensity/layer masks and covers the full keyboard")
    }
}
