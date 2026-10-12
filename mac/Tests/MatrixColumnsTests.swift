import Foundation
@main struct MatrixColumnsTests {
 static func main() throws {
  let keys=try JSONDecoder().decode([KeyGeometry].self,from:Data(contentsOf:URL(fileURLWithPath:"mac/Resources/layout.json")))
  let map=try JSONDecoder().decode(MappingFile.self,from:Data(contentsOf:URL(fileURLWithPath:"mac/Resources/default-led-map.json")))
  assert(Set(LogicalMatrixRaster.assignments.keys)==Set(keys.map(\.id)))
  for id in ["Escape","Backquote","Digit1","Tab","CapsLock","ShiftLeft","ControlLeft"] { assert(LogicalMatrixRaster.assignments[id]! & 31 == 0) }
  for id in ["F1","Digit2","KeyQ","KeyA","KeyZ","AltLeft"] { assert(LogicalMatrixRaster.assignments[id]! & 31 == 1) }
  for (effect,name) in [(LightingEffect.spacedMatrixRain,"spaced"),(.matrixKeyRain,"key")] {
   let settings=LightingSettings(effect:effect,color:RGB(r:0,g:255,b:32))
   let pulses=effect.requiresKeyPresses ? [KeyPulse(keyID:"KeyA",time:0)] : []
   let expected=[UInt8](try Data(contentsOf:URL(fileURLWithPath:"mac/Tests/Fixtures/\(name)-matrix-native-v1.7.bin")))
   assert(expected.count==60*312)
   var reached=Set<String>()
   for i in 0..<60 {
    let frame=LightingRenderer.frame(settings:settings,keys:keys,mapping:map,pulses:pulses,time:Double(i)/10)
    assert(frame.flatMap(\.bytes)==Array(expected[(i*312)..<((i+1)*312)]),"Native/Mac \(effect) parity at frame \(i)")
    for key in keys { let index=map.mappings.first{$0.keyId==key.id}!.ledIndex!;if frame[index] != .black {reached.insert(key.id);let packed=LogicalMatrixRaster.assignments[key.id]!;assert(effect == .spacedMatrixRain ? packed & 1 == 0 : packed & 31 == 1);if i==0 {assert(packed >> 5 == 0)} } }
   }
   let eligible=Set(keys.filter{let p=LogicalMatrixRaster.assignments[$0.id]!;return effect == .spacedMatrixRain ? p & 1 == 0 : p & 31 == 1}.map(\.id));assert(reached==eligible)
   var fast=settings;fast.speed=2
   assert(LightingRenderer.frame(settings:settings,keys:keys,mapping:map,pulses:pulses,time:0.8)==LightingRenderer.frame(settings:fast,keys:keys,mapping:map,pulses:pulses,time:0.4))
   var layer=LightingLayer(settings:settings);layer.keyIDs=["KeyA"];layer.affectAllKeys=true
   let output=LayerRenderer.frame(layers:[layer],keys:keys,mapping:map,pulses:pulses,time:0.2)
   if effect == .matrixKeyRain { assert(output.contains{$0 != .black});assert(LayerRenderer.frame(layers:[layer],keys:keys,mapping:map,pulses:[KeyPulse(keyID:"KeyW",time:0)],time:0.2).allSatisfy{$0 == .black}) }
   layer.affectAllKeys=false;let restricted=LayerRenderer.frame(layers:[layer],keys:keys,mapping:map,pulses:pulses,time:1)
   let a=map.mappings.first{$0.keyId=="KeyA"}!.ledIndex!;assert(restricted.enumerated().allSatisfy{$0.offset==a || $0.element == .black})
   if effect == .matrixKeyRain { assert(LightingRenderer.frame(settings:settings,keys:keys,mapping:map,pulses:pulses,time:6).allSatisfy{$0 == .black}) }
  }
  print("PASS: 120 production-native frames match Mac preview; all104 fixed groups, top-row entry, alternating dark columns, finite key rain, speed and independent masks")
 }
}
