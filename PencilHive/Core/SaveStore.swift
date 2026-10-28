import Foundation

/// Collects whether any field of a save had to be replaced by its default because it was damaged.
final class SaveDamageLog {
    var sawDamage = false
}

extension CodingUserInfoKey {
    static let saveDamageLog = CodingUserInfoKey(rawValue: "pencilhive.saveDamageLog")!
}

private extension KeyedDecodingContainer {
    /// Decodes a value, treating a missing key and a wrong-typed value alike as "not there", so one
    /// damaged field cannot cost the player the rest of the save. A wrong-typed value is noted in
    /// `log` so the caller can keep a copy of the file.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, log: SaveDamageLog?) -> T? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            log?.sawDamage = true
            return nil
        }
    }
}

struct PlayerProgress: Codable, Equatable {
    /// Highest level id the player may open.
    var unlockedLevel: Int = 1
    var bestStars: [Int: Int] = [:]
    var bestScores: [Int: Int] = [:]

    init() {}

    // Fields added in later versions must use decodeIfPresent so older saves still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let log = decoder.userInfo[.saveDamageLog] as? SaveDamageLog
        unlockedLevel = max(1, c.lenient(Int.self, forKey: .unlockedLevel, log: log) ?? 1)
        bestStars = c.lenient([Int: Int].self, forKey: .bestStars, log: log) ?? [:]
        bestScores = c.lenient([Int: Int].self, forKey: .bestScores, log: log) ?? [:]
    }
}

struct GameSettings: Codable, Equatable {
    var soundEnabled = true
    var hapticsEnabled = true
    /// Print a shape on each tile so colours can be told apart. Also switched on by the system
    /// "Differentiate Without Color" setting.
    var tileSymbols = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let log = decoder.userInfo[.saveDamageLog] as? SaveDamageLog
        soundEnabled = c.lenient(Bool.self, forKey: .soundEnabled, log: log) ?? true
        hapticsEnabled = c.lenient(Bool.self, forKey: .hapticsEnabled, log: log) ?? true
        tileSymbols = c.lenient(Bool.self, forKey: .tileSymbols, log: log) ?? false
    }
}

/// A level in progress, so the player can leave and come back.
struct SavedGame: Codable, Equatable {
    var levelID: Int
    var state: GameState
    var history: [GameState]
    /// Absent in older saves. A snapshot prevents a resumed run mixing two level definitions.
    var levelDefinition: LevelDefinition? = nil
}

struct SaveData: Codable, Equatable {
    var version = 1
    var progress = PlayerProgress()
    var settings = GameSettings()
    var inProgress: SavedGame?

    init(version: Int = 1, progress: PlayerProgress = PlayerProgress(), settings: GameSettings = GameSettings(), inProgress: SavedGame? = nil) {
        self.version = version
        self.progress = progress
        self.settings = settings
        self.inProgress = inProgress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let log = decoder.userInfo[.saveDamageLog] as? SaveDamageLog
        version = c.lenient(Int.self, forKey: .version, log: log) ?? 1
        progress = c.lenient(PlayerProgress.self, forKey: .progress, log: log) ?? PlayerProgress()
        settings = c.lenient(GameSettings.self, forKey: .settings, log: log) ?? GameSettings()
        // A damaged game in progress must never cost the player their unlocked levels and stars.
        inProgress = c.lenient(SavedGame.self, forKey: .inProgress, log: log)
    }
}

/// Where the save blob lives. Swappable so tests never touch the disk.
protocol SaveStorage {
    func load() throws -> Data?
    func save(_ data: Data) throws
    /// Keeps a copy of a save file that could not be read, so it is never silently overwritten.
    func preserveUnreadable(_ data: Data)
    /// Keeps a copy of a save file that exists but could not be loaded (for example an I/O error).
    func preserveUnloadableFile()
}

extension SaveStorage {
    func preserveUnreadable(_ data: Data) {}
    func preserveUnloadableFile() {}
}

struct FileSaveStorage: SaveStorage {
    let url: URL

    static var standard: FileSaveStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileSaveStorage(url: base.appendingPathComponent("PencilHive/save.json"))
    }

    func load() throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Each backup gets its own name, so an earlier one is never overwritten.
    private func backupURL() -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let directory = url.deletingLastPathComponent()
        var candidate = directory.appendingPathComponent("save.unreadable-\(stamp).json")
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("save.unreadable-\(stamp)-\(suffix).json")
            suffix += 1
        }
        return candidate
    }

    func preserveUnreadable(_ data: Data) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: backupURL(), options: .atomic)
    }

    func preserveUnloadableFile() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.copyItem(at: url, to: backupURL())
    }
}

final class InMemorySaveStorage: SaveStorage {
    private(set) var data: Data?
    private(set) var preservedUnreadable: Data?
    private(set) var unloadablePreserved = false
    func preserveUnreadable(_ data: Data) { preservedUnreadable = data }
    func preserveUnloadableFile() { unloadablePreserved = true }
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
}

/// Reads and writes `SaveData`. A missing or unreadable file simply starts a fresh save.
final class SaveStore {
    private let storage: SaveStorage
    private(set) var data: SaveData
    /// The bytes last written, so an unchanged state is not written again.
    private var lastWritten: Data?

    init(storage: SaveStorage) {
        self.storage = storage
        do {
            if let raw = try storage.load() {
                let damage = SaveDamageLog()
                let decoder = JSONDecoder()
                decoder.userInfo[.saveDamageLog] = damage
                if let decoded = try? decoder.decode(SaveData.self, from: raw) {
                    data = decoded
                    // Fields that had to fall back to defaults are about to be overwritten by the next
                    // save, so keep the original file for recovery.
                    if damage.sawDamage { storage.preserveUnreadable(raw) }
                    lastWritten = raw
                } else {
                    storage.preserveUnreadable(raw)
                    data = SaveData()
                }
            } else {
                data = SaveData()
            }
        } catch {
            // The file exists but could not be read: copy it aside before a new save replaces it.
            storage.preserveUnloadableFile()
            data = SaveData()
        }
    }

    var progress: PlayerProgress { data.progress }
    var settings: GameSettings { data.settings }

    func isUnlocked(_ levelID: Int) -> Bool { levelID <= max(1, data.progress.unlockedLevel) }

    /// Records a win: keeps the best result and unlocks the next level.
    func recordWin(levelID: Int, nextLevelID: Int?, stars: Int, score: Int) {
        data.progress.bestStars[levelID] = max(stars, data.progress.bestStars[levelID] ?? 0)
        data.progress.bestScores[levelID] = max(score, data.progress.bestScores[levelID] ?? 0)
        if let next = nextLevelID { data.progress.unlockedLevel = max(data.progress.unlockedLevel, next) }
        if data.inProgress?.levelID == levelID { data.inProgress = nil }
        persist()
    }

    func updateSettings(_ change: (inout GameSettings) -> Void) {
        change(&data.settings)
        persist()
    }

    func saveInProgress(_ engine: GameEngine) {
        guard engine.state.status.isPlaying else {
            clearInProgress(levelID: engine.level.id)
            return
        }
        // Merely opening a level must not replace a different level's saved game.
        if engine.state.movesUsed == 0 && engine.undoHistory.isEmpty && engine.boostersUsed == 0 {
            clearInProgress(levelID: engine.level.id)
            return
        }
        data.inProgress = SavedGame(levelID: engine.level.id, state: engine.state,
                                    history: engine.undoHistory, levelDefinition: engine.level)
        persist()
    }

    func clearInProgress(levelID: Int? = nil) {
        guard levelID == nil || data.inProgress?.levelID == levelID else { return }
        data.inProgress = nil
        persist()
    }

    /// Rebuilds the saved engine for `level`, if a matching save exists and still fits the level.
    /// A save that no longer fits (the level changed in an update, or the file is damaged) is
    /// dropped instead of being allowed to crash the game.
    func restoreEngine(for level: LevelDefinition) -> GameEngine? {
        guard let saved = data.inProgress, saved.levelID == level.id else { return nil }
        guard saved.levelDefinition.map({ $0 == level }) ?? true,
              Self.isValid(saved.state, for: level), saved.state.status.isPlaying else {
            clearInProgress(levelID: level.id)
            return nil
        }
        // An undo chain with one bad entry is dropped whole; the current position is still good.
        let history = saved.history.count <= 64 && saved.history.allSatisfy({ Self.isValid($0, for: level) }) ? saved.history : []
        return GameEngine(level: level, state: saved.state, history: history)
    }

    /// True when `state` could have been produced by playing `level`.
    static func isValid(_ state: GameState, for level: LevelDefinition) -> Bool {
        let cells = Set(level.cells)
        guard Set(state.board.cells) == cells, state.board.cells.count == cells.count else { return false }
        guard state.board.stacks.allSatisfy({ cells.contains($0.key) && $0.value.height <= level.maxStackHeight }) else { return false }
        guard state.tray.count == level.trayCount else { return false }
        guard (state.tray.compactMap { $0 } + state.queue).allSatisfy({ !$0.isEmpty }) else { return false }
        let regionIDs = Set(level.artwork.regions.map(\.id))
        guard Set(state.filledRegions).count == state.filledRegions.count,
              state.filledRegions.allSatisfy(regionIDs.contains) else { return false }
        // Counters far beyond anything a real game reaches would overflow the arithmetic that
        // follows (win bonus, score), so a damaged save is refused here instead.
        guard (state.tray.compactMap { $0 } + state.queue).allSatisfy({ $0.height <= level.maxStackHeight }) else { return false }
        guard state.pencilsByColor.values.allSatisfy({ (0...10_000).contains($0) }) else { return false }
        let boosters = state.boosters
        return (0...100_000).contains(state.movesUsed)
            // Placement consumes one supply entry. Refresh only rotates entries; Hammer does
            // not consume one, and Undo restores both counts. This also rejects legacy saves
            // from before supply entries were added, without clearing earned progress/settings.
            && state.movesUsed + state.tray.compactMap({ $0 }).count + state.queue.count == level.supply.count
            && (0...100_000_000).contains(state.score)
            && (0...1_000).contains(state.bestChain)
            && [boosters.undo, boosters.hammer, boosters.refresh].allSatisfy { (0...99).contains($0) }
    }

    func resetAll() {
        data = SaveData(version: data.version, progress: PlayerProgress(), settings: data.settings, inProgress: nil)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // equal states must encode to equal bytes
        guard let encoded = try? encoder.encode(data), encoded != lastWritten else { return }
        if (try? storage.save(encoded)) != nil { lastWritten = encoded }
    }
}
