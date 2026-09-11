import Foundation
struct KeyGeometry: Decodable, Identifiable {
    let id: String; let label: String; let x: Double; let y: Double; let width: Double; let height: Double
}
struct KeyMapping: Codable {
    var keyId: String; var ledIndex: Int?; var confirmed: Bool
}
struct MappingFile: Codable {
    var schemaVersion: Int; var layoutId: String; var ledCount: Int; var mappings: [KeyMapping]
    static func rowOrder(keys: [KeyGeometry]) throws -> MappingFile {
        // The LEDs in the tall numpad + and Enter keys belong to their lower row.
        let ordered = keys.sorted {
            let row0 = $0.y + $0.height - 1, row1 = $1.y + $1.height - 1
            return row0 == row1 ? $0.x < $1.x : row0 < row1
        }
        let result = MappingFile(schemaVersion: 1, layoutId: "ansi-104", ledCount: 104,
                                 mappings: ordered.enumerated().map {
            KeyMapping(keyId: $0.element.id, ledIndex: $0.offset, confirmed: true)
        })
        try result.validate(keys: keys)
        try require(result.mappings.first?.keyId == "Escape", "Row order must begin with Escape.")
        return result
    }
    func validate(keys: [KeyGeometry]) throws {
        try require(schemaVersion == 1 && layoutId == "ansi-104" && ledCount == 104, "Unsupported mapping file format.")
        try require(mappings.count == 104 && Set(mappings.map(\.keyId)) == Set(keys.map(\.id)), "Mapping must contain all 104 unique key IDs.")
        let indices = mappings.compactMap(\.ledIndex)
        try require(indices.allSatisfy { (0..<104).contains($0) } && Set(indices).count == indices.count, "Mapping contains duplicate or invalid LED indices.")
        try require(mappings.allSatisfy { !$0.confirmed || $0.ledIndex != nil }, "Confirmed key is missing its LED index.")
    }
    mutating func assign(key: String, index: Int) {
        for i in mappings.indices {
            if mappings[i].ledIndex == index { mappings[i].ledIndex = nil; mappings[i].confirmed = false }
        }
        if let i = mappings.firstIndex(where: { $0.keyId == key }) {
            mappings[i].ledIndex = index; mappings[i].confirmed = true
        }
    }
    static var saveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GMK104RgbController/led-map.json")
    }
    func save(keys: [KeyGeometry]) throws {
        try validate(keys: keys)
        let url = Self.saveURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
