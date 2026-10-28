import Foundation

enum LevelLibraryError: Error, CustomStringConvertible {
    case noLevelsFound
    case invalid([String])

    var description: String {
        switch self {
        case .noLevelsFound: return "No level files found"
        case .invalid(let problems): return "Invalid level data:\n" + problems.joined(separator: "\n")
        }
    }
}

/// The ordered list of playable levels.
struct LevelLibrary {
    let levels: [LevelDefinition]

    init(levels: [LevelDefinition]) {
        self.levels = levels.sorted { $0.id < $1.id }
    }

    func level(id: Int) -> LevelDefinition? { levels.first { $0.id == id } }

    func level(after id: Int) -> LevelDefinition? {
        levels.first { $0.id > id }
    }

    var first: LevelDefinition? { levels.first }

    /// Decodes and validates level JSON documents.
    static func decode(_ documents: [Data]) throws -> LevelLibrary {
        let decoder = JSONDecoder()
        let levels = try documents.map { try decoder.decode(LevelDefinition.self, from: $0) }
        guard !levels.isEmpty else { throw LevelLibraryError.noLevelsFound }
        let problems = levels.flatMap(LevelValidator.validate)
        guard problems.isEmpty else { throw LevelLibraryError.invalid(problems) }
        guard Set(levels.map(\.id)).count == levels.count else { throw LevelLibraryError.invalid(["Duplicate level ids"]) }
        return LevelLibrary(levels: levels)
    }

    /// Loads every `*.json` file in a directory (used by tests and tools).
    static func load(directory: URL) throws -> LevelLibrary {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try decode(files.map { try Data(contentsOf: $0) })
    }

    /// Loads the levels shipped in the app bundle's `Levels` folder.
    static func bundled(in bundle: Bundle = .main) throws -> LevelLibrary {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Levels"), !urls.isEmpty else {
            throw LevelLibraryError.noLevelsFound
        }
        return try decode(urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { try Data(contentsOf: $0) })
    }
}
