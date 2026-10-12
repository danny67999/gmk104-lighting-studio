import AppKit
import SwiftUI
import Foundation

// Render the actual production views, using mock USB and temporary profiles.
// This does not claim physical mouse/keyboard testing or a live keyboard save.
@main struct StudioSnapshot {
    static func pump(_ seconds:Double=0.2) { RunLoop.main.run(until:Date().addingTimeInterval(seconds)) }
    static func awaitIdle(_ model:ControllerModel) throws {
        let limit=Date().addingTimeInterval(3)
        while model.busy && Date() < limit { pump(0.01) }
        try require(!model.busy,"UI fixture did not finish")
    }
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let output=root.appendingPathComponent("outputs/Lighting Studio 1.8.7/UI")
        let fixture=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("gmk104-ui-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:fixture,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let bus=MockBus();bus.previewFirmware=true;bus.persistentFirmware=true;bus.spacedEffects=true;bus.inputPermission = .granted
        let model=ControllerModel(environment:ControllerEnvironment(
            layoutURL:root.appendingPathComponent("mac/Resources/layout.json"),defaultMappingURL:root.appendingPathComponent("mac/Resources/default-led-map.json"),
            mappingURL:fixture.appendingPathComponent("mapping.json"),profileURL:fixture.appendingPathComponent("profile.json"),
            openTransport:{ try bus.open() },attachments:{ bus.snapshot() },inputMonitoringEnabled:false,
            readInputPermission:{ bus.inputPermission },requestInputPermission:{ false },connectionInterval:3600))
        var ripple=LightingLayer(name:"WASD ripple",settings:LightingSettings(effect:.rainbowRipple))
        ripple.keyIDs=["KeyW","KeyA","KeyS","KeyD"];ripple.affectAllKeys=true
        model.layers=[LightingLayer(name:"Spaced Matrix",settings:LightingSettings(effect:.spacedMatrixRain,color:RGB(r:0,g:255,b:32))),ripple,
                      LightingLayer(name:"Background",settings:LightingSettings(effect:.staticColor,color:RGB(r:0,g:10,b:4)))]
        model.selectedLayerID=model.layers.first?.id
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        let window=NSWindow(contentRect:NSRect(x:20000,y:20000,width:1160,height:800),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="GMK104 Lighting Studio · mock UI"
        let viewState=StudioViewState(page:.myLighting)
        let host=NSHostingView(rootView:AnyView(ControllerView(model:model,viewState:viewState).environment(\.colorScheme,.light)))
        window.contentView=host;window.orderFrontRegardless()
        func capture(_ name:String,_ view:NSView?=nil) throws {
            pump();let target=view ?? host;target.layoutSubtreeIfNeeded();target.displayIfNeeded()
            let bitmap=target.bitmapImageRepForCachingDisplay(in:target.bounds)!
            target.cacheDisplay(in:target.bounds,to:bitmap)
            // Sheet hosting views are transparent; include their native backdrop.
            let composite=NSImage(size:target.bounds.size)
            composite.lockFocus()
            NSColor.windowBackgroundColor.setFill();NSBezierPath(rect:target.bounds).fill()
            bitmap.size=target.bounds.size;bitmap.draw(in:target.bounds)
            composite.unlockFocus()
            let png=NSBitmapImageRep(data:composite.tiffRepresentation!)!.representation(using:.png,properties:[:])!
            try png.write(to:output.appendingPathComponent(name+".png"))
        }
        func captureSheet(_ name:String,_ kind:String,_ width:CGFloat,_ height:CGFloat) throws {
            // Render the same sheet view directly. Window-server sheet surfaces
            // are not completely included by NSView.cacheDisplay on this SDK.
            let sheetHost=NSHostingView(rootView:ControllerView(model:model,viewState:viewState).snapshotSheet(kind).environment(\.colorScheme,.light))
            let review=NSWindow(contentRect:NSRect(x:20000,y:20000,width:width,height:height),styleMask:[.titled],backing:.buffered,defer:false)
            review.appearance=NSAppearance(named:.aqua);review.contentView=sheetHost;review.orderFront(nil)
            try capture(name,sheetHost);review.orderOut(nil)
        }
        // Verify the same view inherits system appearance, without an override.
        host.rootView = AnyView(ControllerView(model:model,viewState:viewState))
        try require(window.appearance == nil,"Window must inherit system appearance")
        try require(window.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == app.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]),"System appearance differs from app window")
        try capture("00-system-appearance")
        window.appearance=NSAppearance(named:.aqua)
        host.rootView=AnyView(ControllerView(model:model,viewState:viewState).environment(\.colorScheme,.light))
        try capture("01-offline")
        bus.attach(9101);model.connect();try awaitIdle(model)
        try require(model.onboardPersistentAvailable,"Initial connection did not discover Save")
        try capture("02-connected")
        model.checkOnboardPreviewSupport();try awaitIdle(model);try capture("03-after-check")
        model.addLayer(.keyToggle);try capture("04-after-add")
        model.saveOnKeyboard();try awaitIdle(model)
        try require(model.onboardPreviewActive,"Mock save was not verified")
        try capture("05-after-save")
        for _ in 0..<3 { model.checkOnboardPreviewSupport();try awaitIdle(model) }
        try require(model.onboardPreviewActive,"Support refresh lost native playback")
        try capture("06-after-repeat-check")
        window.appearance=NSAppearance(named:.darkAqua)
        host.rootView=AnyView(ControllerView(model:model,viewState:viewState).environment(\.colorScheme,.dark))
        try capture("07-dark-workspace")
        window.appearance=NSAppearance(named:.aqua)
        host.rootView=AnyView(ControllerView(model:model,viewState:viewState).environment(\.colorScheme,.light))
        viewState.page = .allEffects;try capture("08-gallery")
        viewState.page = .keyboard;try capture("09-keyboard-access")
        viewState.showingMacPlayback=true;pump(0.3)
        try require(window.attachedSheet != nil,"Mac Playback sheet did not open")
        try captureSheet("11-mac-playback","Mac",600,480)
        viewState.showingMacPlayback=false;pump(0.3)
        try require(window.attachedSheet == nil,"Mac Playback sheet did not dismiss")
        viewState.page = .myLighting;model.selectedLayerID=ripple.id;pump(0.3)
        try require(model.selectingLayerKeys,"My Lighting must select keys without opening an editor")
        try capture("12-inline-editor")
        try require(window.attachedSheet == nil,"Layer editing must remain inline")
        model.applyPreset(.synthwave);try capture("13-preset")
        model.removeAllEffects();try capture("14-empty-workspace")
        model.undoWorkspace();try require(model.layers.count == 3,"Undo must restore preset layers")
        model.disconnect();try awaitIdle(model);try capture("10-disconnected")
        try require(!FileManager.default.fileExists(atPath:fixture.appendingPathComponent("profile.json").path),"UI checks must not create Mac profiles")
        print("PASS: fifteen actual SwiftUI snapshots rendered across offline/connect/check/add/mock save/repeated check/light/dark/gallery/settings/disconnect and inline editing.")
        print("PASS: Mac Playback opens and dismisses; effect editing stays on My Lighting with selection enabled. Real pointer gestures were not automated.")
        print("No physical keyboard or user profile was accessed; only mock USB and temporary profiles were used.")
    }
}
