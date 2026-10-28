import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

/// Storage that counts writes and can be told to fail its first read.
private final class RecordingStorage: SaveStorage {
    var stored: Data?
    var writes = 0
    var failLoad = false
    var preservedFile = false
    func load() throws -> Data? {
        if failLoad { throw CocoaError(.fileReadNoPermission) }
        return stored
    }
    func save(_ data: Data) throws { stored = data; writes += 1 }
    func preserveUnloadableFile() { preservedFile = true }
}

@Suite("Saves that do not fit the level")
struct SaveValidationTests {
    private let origin = TestLevels.cell(0, 0)

    private func level() -> LevelDefinition {
        TestLevels.make(supply: [[.coral], [.sky], [.mint], [.lemon]], regions: [.coral, .sky])
    }

    /// A store whose file holds `state` as the game in progress for the test level.
    private func store(holding state: GameState, history: [GameState] = []) throws -> SaveStore {
        let storage = InMemorySaveStorage()
        let data = SaveData(inProgress: SavedGame(levelID: level().id, state: state, history: history))
        try storage.save(JSONEncoder().encode(data))
        return SaveStore(storage: storage)
    }

    private func playedEngine() -> GameEngine {
        var engine = GameEngine(level: level())
        engine.place(slot: 0, at: origin)
        return engine
    }

    @Test func aMatchingSaveStillRestores() throws {
        let saved = playedEngine()
        let store = try store(holding: saved.state, history: saved.undoHistory)
        let restored = try #require(store.restoreEngine(for: level()))
        #expect(restored.state == saved.state)
        #expect(restored.undoHistory == saved.undoHistory)
    }

    @Test func aSaveWithAnotherBoardShapeIsDroppedNotCrashed() throws {
        let bigger = TestLevels.make(radius: 3, supply: [[.coral]], regions: [.coral])
        let store = try store(holding: GameEngine(level: bigger).state)
        #expect(store.restoreEngine(for: level()) == nil)
        #expect(store.data.inProgress == nil)
    }

    @Test func aSaveWithAWrongTrayIsDropped() throws {
        var state = playedEngine().state
        state.tray.append(nil)
        let store = try store(holding: state)
        #expect(store.restoreEngine(for: level()) == nil)
    }

    @Test func aSaveWithUnknownArtworkRegionsIsDropped() throws {
        var state = playedEngine().state
        state.filledRegions = [1, 77]
        let store = try store(holding: state)
        #expect(store.restoreEngine(for: level()) == nil)
    }

    @Test func aSaveWithATooTallStackIsDropped() throws {
        let short = TestLevels.make(supply: [[.coral]], regions: [.coral], maxStackHeight: 2)
        var state = GameEngine(level: short).state
        state.board.setStack(TileStack([.sky, .sky, .sky]), at: origin)
        let storage = InMemorySaveStorage()
        try storage.save(JSONEncoder().encode(SaveData(inProgress: SavedGame(levelID: short.id, state: state, history: []))))
        #expect(SaveStore(storage: storage).restoreEngine(for: short) == nil)
    }

    @Test func aBadUndoHistoryIsDroppedButTheGameIsKept() throws {
        let saved = playedEngine()
        var stale = saved.state
        stale.tray.append(nil)
        let store = try store(holding: saved.state, history: [stale])
        let restored = try #require(store.restoreEngine(for: level()))
        #expect(restored.state == saved.state)
        #expect(restored.undoHistory.isEmpty)
    }

    @Test func aFailedGameIsNotRestoredAsPlayable() throws {
        var state = playedEngine().state
        state.status = .failed(.outOfSupply)
        let store = try store(holding: state)
        #expect(store.restoreEngine(for: level()) == nil)
    }

    @Test func anOldSupplySaveIsDroppedWithoutLosingEarnedProgressOrSettings() throws {
        let saved = playedEngine()
        var progress = PlayerProgress()
        progress.unlockedLevel = 7
        progress.bestStars = [1: 3, 2: 2]
        progress.bestScores = [1: 900, 2: 1100]
        var settings = GameSettings()
        settings.soundEnabled = false
        settings.hapticsEnabled = false
        settings.tileSymbols = true
        let storage = InMemorySaveStorage()
        // No definition metadata: this is the format shipped before the recovery supply update.
        let legacy = SaveData(progress: progress, settings: settings,
            inProgress: SavedGame(levelID: level().id, state: saved.state, history: saved.undoHistory))
        try storage.save(JSONEncoder().encode(legacy))
        let updated = TestLevels.make(supply: [[.coral], [.sky], [.mint], [.lemon], [.sky]], regions: [.coral, .sky])
        let store = SaveStore(storage: storage)
        #expect(store.restoreEngine(for: updated) == nil)
        let reloaded = SaveStore(storage: storage)
        #expect(reloaded.data.inProgress == nil)
        #expect(reloaded.progress == progress)
        #expect(reloaded.settings == settings)
    }

    @Test func aChangedDealOfTheSameLengthCannotReuseANewSave() throws {
        let storage = InMemorySaveStorage()
        SaveStore(storage: storage).saveInProgress(playedEngine())
        let changed = TestLevels.make(supply: [[.coral], [.sky], [.mint], [.violet]], regions: [.coral, .sky])
        let store = SaveStore(storage: storage)
        #expect(store.restoreEngine(for: changed) == nil)
        #expect(store.data.inProgress == nil)
    }

    @Test func legacyRunsRemainCompatibleAfterBoostersAndUndo() throws {
        var engine = playedEngine()
        let refreshed = engine.useRefresh()
        #expect(!refreshed.isEmpty)
        let hammered = engine.useHammer(at: origin)
        #expect(!hammered.isEmpty)
        let undone = engine.undo()
        #expect(undone)
        let store = try store(holding: engine.state, history: engine.undoHistory)
        let restored = try #require(store.restoreEngine(for: level()))
        #expect(restored.state == engine.state)
        #expect(restored.undoHistory == engine.undoHistory)
    }

    @Test func anUndoSnapshotWithMissingSupplyIsDroppedWithoutLosingTheRun() throws {
        let engine = playedEngine()
        var invalid = try #require(engine.undoHistory.first)
        invalid.queue.removeLast()
        let store = try store(holding: engine.state, history: [invalid])
        let restored = try #require(store.restoreEngine(for: level()))
        #expect(restored.state == engine.state)
        #expect(restored.undoHistory.isEmpty)
    }
}

@Suite("Save file safety")
struct SaveFileSafetyTests {
    @Test func olderSavesWithMissingFieldsStillLoad() throws {
        let storage = InMemorySaveStorage()
        try storage.save(Data(#"{"progress": {"unlockedLevel": 3}}"#.utf8))
        let store = SaveStore(storage: storage)
        #expect(store.progress.unlockedLevel == 3)
        #expect(store.settings == GameSettings())
        #expect(storage.preservedUnreadable == nil)
    }

    @Test func aDamagedGameInProgressDoesNotCostTheProgress() throws {
        let storage = InMemorySaveStorage()
        try storage.save(Data(#"{"progress": {"unlockedLevel": 3, "bestStars": {"1": 2}}, "inProgress": {"levelID": 1}}"#.utf8))
        let store = SaveStore(storage: storage)
        #expect(store.progress.unlockedLevel == 3)
        #expect(store.progress.bestStars[1] == 2)
        #expect(store.data.inProgress == nil)
    }

    @Test func aFileThatCannotBeReadIsCopiedAsideBeforeBeingReplaced() {
        let storage = RecordingStorage()
        storage.failLoad = true
        let store = SaveStore(storage: storage)
        #expect(storage.preservedFile)
        #expect(store.progress == PlayerProgress())
    }

    @Test func eachUnreadableSaveGetsItsOwnBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pencil-hive-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("save.json")
        let storage = FileSaveStorage(url: file)

        try Data("first".utf8).write(to: file)
        _ = SaveStore(storage: storage)
        try Data("second".utf8).write(to: file)
        _ = SaveStore(storage: storage)

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("save.unreadable") }
        #expect(backups.count == 2)
        let contents = try Set(backups.map { try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) })
        #expect(contents == ["first", "second"])
    }

    @Test func anUnchangedStateIsNotWrittenTwice() {
        let storage = RecordingStorage()
        let store = SaveStore(storage: storage)
        let level = TestLevels.make(supply: [[.coral], [.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: TestLevels.cell(0, 0))
        store.saveInProgress(engine)
        store.saveInProgress(engine)
        #expect(storage.writes == 1)
        store.updateSettings { $0.soundEnabled = false }
        #expect(storage.writes == 2)
    }
}

@Suite("Height cap")
struct HeightCapTests {
    @Test func aBlockedMergeIsRetriedInTheOtherDirection() {
        // The placed stack (height 4) cannot take the neighbour's two coral tiles under a cap of 4,
        // but the neighbour (height 2) can take the placed stack's single coral tile.
        let level = TestLevels.make(
            pencilSize: 4, prefilled: [(TestLevels.cell(1, 0), [.coral, .coral])],
            supply: [[.sky, .sky, .sky, .coral]], regions: [.coral], maxStackHeight: 4)
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: TestLevels.cell(0, 0))
        #expect(events.transfers.count == 1)
        #expect(engine.state.board.stack(at: TestLevels.cell(0, 0)) == TileStack([.sky, .sky, .sky]))
        #expect(engine.state.board.stack(at: TestLevels.cell(1, 0)) == TileStack([.coral, .coral, .coral]))
        #expect(engine.state.board.isStable)
    }

    @Test func aReverseMergePencilDoesNotInflateChainDepth() {
        let level = TestLevels.make(
            pencilSize: 4, prefilled: [(TestLevels.cell(1, 0), [.coral, .coral, .coral])],
            supply: [[.sky, .sky, .sky, .coral]], regions: [.coral, .sky], maxStackHeight: 4)
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: TestLevels.cell(0, 0))
        #expect(events.pencils == [.pencilCompleted(cell: TestLevels.cell(1, 0), color: .coral, tileCount: 4, regionID: 1, chain: 0)])
        // 1 transferred tile (10) + 4-tile pencil at chain 0 (100).
        #expect(engine.state.score == 110)
    }

    @Test func randomPlayoutsKeepEveryTileAndNeverTrap() throws {
        for level in try LevelLibrary.load(directory: TestLevels.levelsDirectory).levels {
            var seed = UInt64(level.id) &* 0x9E37_79B9_7F4A_7C15 | 1
            func next(_ bound: Int) -> Int {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Int((seed >> 33) % UInt64(bound))
            }
            let total = level.tileBudget.values.reduce(0, +)
            for _ in 0..<25 {
                var engine = GameEngine(level: level)
                var cleared = 0
                while engine.state.status.isPlaying {
                    let slots = engine.state.tray.indices.filter { engine.state.tray[$0] != nil }
                    let cells = engine.legalCells
                    guard let slot = slots.isEmpty ? nil : slots[next(slots.count)], !cells.isEmpty else { break }
                    for case let .pencilCompleted(_, _, count, _, _) in engine.place(slot: slot, at: cells[next(cells.count)]) {
                        cleared += count
                    }
                    let onTable = engine.state.board.tileCount
                        + engine.state.trayStacks.reduce(0) { $0 + $1.height }
                        + engine.state.queue.reduce(0) { $0 + $1.height }
                    #expect(onTable + cleared == total, "Level \(level.id) lost or invented tiles")
                }
            }
        }
    }
}
