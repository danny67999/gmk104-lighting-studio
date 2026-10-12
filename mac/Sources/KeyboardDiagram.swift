import SwiftUI
import AppKit

private final class KeyboardDiagramInteraction: ObservableObject {
    @Published var drag: KeySelectionDrag?
    var previewing = false
}

struct KeyboardDiagram: View {
    @ObservedObject var model: ControllerModel
    var selectionTool: KeySelectionTool = .automatic
    var canvasHeight:CGFloat = 276
    @StateObject private var interaction = KeyboardDiagramInteraction()
    private var canSelect: Bool { model.selectingLayerKeys && !model.mappingMode && !model.busy && model.map != nil && !model.layers.isEmpty }
    var body: some View {
        TimelineView(.periodic(from: .now,by: 1.0/20)) { _ in
            let preview = model.mappingMode ? model.frame : model.draftPreviewFrame()
            GeometryReader { geometry in
                let unit = min((geometry.size.width-28)/23,(geometry.size.height-28)/6.5)
                ZStack(alignment: .topLeading) {
                    ForEach(model.keys) { key in
                        let mapping = model.map?.mappings.first { $0.keyId == key.id }
                        let known = mapping?.confirmed == true
                        let color = keyColor(mapping,preview: preview)
                        let selected = model.mappingMode ? model.selectedMappingKey == key.id : model.selectingLayerKeys && model.layerIncludes(key)
                        let highlighted = selected && (model.mappingMode || model.selectedLayer.keyIDs != nil)
                        Button {
                            if model.mappingMode || model.selectingLayerKeys { model.click(key) }
                            else { model.previewDraftPulse(key.id) }
                        } label: {
                            VStack(spacing: 3) {
                                Text(key.label).font(.system(size:10,weight:.medium)).multilineTextAlignment(.center)
                                    .lineLimit(key.label.contains("\n") ? 3 : 1).minimumScaleFactor(0.65)
                                if model.mappingMode,let index = mapping?.ledIndex {
                                    Text("\(index)").font(.system(size:8,design:.monospaced)).foregroundStyle(.secondary)
                                } else if !known { Circle().fill(.gray).frame(width:3,height:3) }
                            }.frame(width:key.width*unit-4,height:key.height*unit-4)
                                .contentShape(Rectangle())
                                .background(color.opacity(0.18),in:RoundedRectangle(cornerRadius:6))
                                .background(highlighted ? Color.accentColor.opacity(0.12) : Color.clear,in:RoundedRectangle(cornerRadius:6))
                                .background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:6))
                                .overlay(RoundedRectangle(cornerRadius:6).stroke(highlighted ? Color.accentColor.opacity(0.55) : known ? color.opacity(0.4) : Color.gray.opacity(0.25),lineWidth:highlighted ? 1 : 0.75))
                        }.buttonStyle(.plain)
                            .disabled(model.busy || model.map == nil || (model.mappingMode && !model.connected))
                            .allowsHitTesting(!canSelect)
                            .opacity(model.selectingLayerKeys && !model.layerIncludes(key) ? 0.65 : 1)
                            .accessibilityLabel(key.id).accessibilityIdentifier("key-"+key.id)
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                            .help(known ? "\(key.id) • LED \(mapping?.ledIndex ?? 0)" : "\(key.id) • LED not yet mapped")
                            .offset(x:14+key.x*unit+2,y:14+key.y*unit+2)
                    }
                    if let rect = interaction.drag?.rectangle {
                        Rectangle().fill(Color.accentColor.opacity(0.14))
                            .overlay(Rectangle().stroke(Color.white,lineWidth:2))
                            .overlay(Rectangle().stroke(Color.accentColor,style:StrokeStyle(lineWidth:1,dash:[4,3])))
                            .frame(width:rect.width*unit,height:rect.height*unit)
                            .offset(x:14+rect.minX*unit,y:14+rect.minY*unit).allowsHitTesting(false)
                    }
                }.frame(width:geometry.size.width,height:geometry.size.height,alignment:.topLeading)
                    .contentShape(Rectangle())
                    .highPriorityGesture(DragGesture(minimumDistance:0,coordinateSpace:.local)
                        .onChanged { value in updateDrag(value,unit:unit) }
                        .onEnded { value in
                            if !interaction.previewing { updateDrag(value,unit:unit) }
                            interaction.drag = nil;interaction.previewing = false
                        },
                        including: canSelect ? .all : .none)
            }.frame(height:canvasHeight)
                .background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:12))
        }.onChange(of:model.selectingLayerKeys) { if !$0 { interaction.drag = nil;interaction.previewing = false } }
            .onChange(of:model.selectedLayer.id) { _ in interaction.drag = nil;interaction.previewing = false }
            .onChange(of:model.busy) { if $0 { interaction.drag = nil;interaction.previewing = false } }
    }
    private func updateDrag(_ value: DragGesture.Value,unit:CGFloat) {
        guard canSelect,unit > 0 else { interaction.drag = nil;return }
        if interaction.previewing { return }
        if interaction.drag == nil && NSEvent.modifierFlags.contains(.command) {
            interaction.previewing = true
            let point=CGPoint(x:(value.startLocation.x-14)/unit,y:(value.startLocation.y-14)/unit)
            if let key=model.keys.first(where:{ KeySelectionDrag.bounds($0,inset:2/unit).contains(point) }) { model.previewDraftPulse(key.id) }
            return
        }
        if interaction.drag == nil {
            interaction.drag = KeySelectionDrag(tool:selectionTool,
                start:CGPoint(x:(value.startLocation.x-14)/unit,y:(value.startLocation.y-14)/unit),
                initial:Set(model.selectedLayer.keyIDs ?? model.keys.map(\.id)),keys:model.keys,
                adding:NSEvent.modifierFlags.contains(.shift),removing:NSEvent.modifierFlags.contains(.option),inset:2/unit)
        }
        let selected = interaction.drag!.update(to:CGPoint(x:(value.location.x-14)/unit,y:(value.location.y-14)/unit),keys:model.keys)
        model.setLayerKeys(selected.count == model.keys.count ? nil : Array(selected))
    }
    private func keyColor(_ mapping:KeyMapping?,preview:[RGB]?) -> Color {
        guard let mapping,mapping.confirmed,let index = mapping.ledIndex else { return .gray }
        guard let preview,preview.indices.contains(index) else { return Color(nsColor:.separatorColor) }
        return ControllerModel.color(preview[index])
    }
}
