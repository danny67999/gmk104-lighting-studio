import Foundation

enum LightingProfileMode: String, Codable { case studio, builtIn, frame }
struct LightingProfile: Codable {
    var version = 2
    var mode: LightingProfileMode
    var settings: LightingSettings
    var builtInEffect: Int = 1
    var colors: [RGB]?
    var restoreOnReconnect = true
    var resume = true
    var layers: [LightingLayer]?

    init(mode: LightingProfileMode, settings: LightingSettings, builtInEffect: Int = 1,
         colors: [RGB]? = nil, restoreOnReconnect: Bool = true, resume: Bool = true,
         layers: [LightingLayer]? = nil) {
        self.mode = mode; self.settings = settings; self.builtInEffect = builtInEffect
        self.colors = colors; self.restoreOnReconnect = restoreOnReconnect; self.resume = resume
        self.layers = layers ?? (mode == .studio ? [LightingLayer(settings: settings)] : nil)
    }

    var studioLayers: [LightingLayer] {
        if let layers { return layers }
        var legacy = LightingLayer(settings: settings)
        legacy.id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        return [legacy]
    }

    func validate() throws {
        try require(version == 1 || version == 2, "Unsupported saved lighting profile.")
        try settings.validate()
        if let layers { try LightingLayer.validate(layers) }
        if version == 2 && mode == .studio { try require(layers != nil, "Saved studio profile is missing its layers.") }
        try require((0...18).contains(builtInEffect), "Saved built-in effect is invalid.")
        if mode == .frame { try require(colors?.count == 104, "Saved lighting frame must contain 104 colors.") }
    }
    static var url: URL { MappingFile.saveURL.deletingLastPathComponent().appendingPathComponent("lighting-profile.json") }
    func save(to url: URL = Self.url) throws {
        try validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
    static func load(from url: URL = Self.url) throws -> LightingProfile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let p = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try p.validate(); return p
    }
}
