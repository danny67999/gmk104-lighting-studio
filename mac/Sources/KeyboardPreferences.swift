import Foundation

struct KeyboardPreferences: Codable {
    var sleepSeconds: Int
    static let choices = [60, 120, 300, 600, 900, 1800, 3600, 0]
    static func label(_ seconds: Int) -> String { seconds == 0 ? "Never" : "\(seconds / 60) min" }
    func validate() throws {
        try require(sleepSeconds == 0 || (60...3600).contains(sleepSeconds), "Invalid saved keyboard sleep time.")
    }
    static func load(from url: URL) throws -> Self? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try result.validate(); return result
    }
    func save(to url: URL) throws {
        try validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
