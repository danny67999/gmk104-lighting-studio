import SwiftUI
import Foundation

private final class EffectPreviewClock: ObservableObject {
    @Published var startedAt = Date()
}

struct EffectKeyboardThumbnail: View {
    let keys: [KeyGeometry]
    let mapping: MappingFile?
    let settings: LightingSettings
    var layer: LightingLayer? = nil
    @StateObject private var previewClock = EffectPreviewClock()
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            Canvas { context, size in
                guard let mapping else { return }
                let t = max(0, timeline.date.timeIntervalSince(previewClock.startedAt))
                let phase = t.truncatingRemainder(dividingBy: 3.5)
                let mappedKeys = mapping.mappings.filter { $0.ledIndex != nil }.map(\.keyId)
                let trigger = ["KeyW"].first { mappedKeys.contains($0) && (layer?.acceptsTrigger($0) ?? true) }
                    ?? mappedKeys.first { layer?.acceptsTrigger($0) ?? true } ?? "KeyW"
                let pulses = [KeyPulse(keyID: trigger, time: t - phase)]
                let held: Set<String> = phase < 1.1 ? [trigger] : []
                let frame = layer.map { LayerRenderer.frame(layers: [$0], keys: keys, mapping: mapping, pulses: pulses, time: t, heldKeys: held, toggledKeys: held) } ?? LightingRenderer.frame(settings: settings, keys: keys, mapping: mapping, pulses: pulses, time: t, heldKeys: held, toggledKeys: held)
                let unit = min(size.width / 23, size.height / 6.5)
                let dx = (size.width - unit * 23) / 2
                for key in keys {
                    guard let index = mapping.mappings.first(where: { $0.keyId == key.id })?.ledIndex else { continue }
                    let color = frame[index]
                    let rect = CGRect(x: dx + key.x * unit, y: key.y * unit, width: max(1, key.width * unit - 1.2), height: max(1, key.height * unit - 1.2))
                    let path = Path(roundedRect: rect, cornerRadius: max(1, unit * 0.12))
                    context.fill(path, with: .color(ControllerModel.color(color)))
                    context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 0.45)
                }
            }
        }.accessibilityLabel("Animated \(settings.effect.displayName) preview")
            .onChange(of: settings.effect) { _ in previewClock.startedAt = Date() }
    }
}
