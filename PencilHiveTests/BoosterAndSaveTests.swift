import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Boosters")
struct BoosterTests {
    private let origin = TestLevels.cell(0, 0)

    @Test func undoRestoresThePreviousStateAndSpendsACharge() {
        let level = TestLevels.make(prefilled: [(TestLevels.cell(1, 0), [.sky])], supply: [[.sky], [.mint]], regions: [.violet])
        var engine = GameEngine(level: level)
        let before = engine.state
        engine.place(slot: 0, at: origin)
        #expect(engine.state != before)
        let outcome2 = engine.undo()
        #expect(outcome2)
        var expected = before
        expected.boosters.undo -= 1
        #expect(engine.state == expected)
    }

    @Test func undoIsNotAllowedAfterAWin() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral]], regions: [.coral])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(!engine.canUndo)
        let undone = engine.undo()
        #expect(!undone)
        if case .won = engine.state.status {} else { Issue.record("win was reverted: \(engine.state.status)") }
    }

    @Test func undoWithoutHistoryOrChargesDoesNothing() {
        var engine = GameEngine(level: TestLevels.make(supply: [[.sky]], regions: [.violet]))
        let outcome3 = !engine.undo()
        #expect(outcome3)
        let noUndo = TestLevels.make(supply: [[.sky]], regions: [.violet], boosters: BoosterInventory())
        var other = GameEngine(level: noUndo)
        other.place(slot: 0, at: origin)
        #expect(!other.canUndo)
    }

    @Test func undoCanStepBackSeveralMoves() {
        let level = TestLevels.make(supply: [[.sky], [.mint], [.lemon]], regions: [.violet])
        var engine = GameEngine(level: level)
        let start = engine.state
        engine.place(slot: 0, at: TestLevels.cell(-2, 0))
        engine.place(slot: 1, at: TestLevels.cell(2, 0))
        let outcome4 = engine.undo()
        #expect(outcome4)
        #expect(engine.state.board.occupiedCells == [TestLevels.cell(-2, 0)])
        let outcome5 = engine.undo()
        #expect(outcome5)
        #expect(engine.state.board == start.board)
        #expect(engine.state.boosters.undo == 1)
    }

    @Test func undoCanRescueAFailedLevel() {
        let level = TestLevels.make(supply: [[.sky]], regions: [.violet], moveLimit: 1)
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(engine.state.status == .failed(.outOfMoves))
        let outcome6 = engine.undo()
        #expect(outcome6)
        #expect(engine.state.status == .playing)
        #expect(engine.movesRemaining == 1)
    }

    @Test func hammerRemovesAStackAndSpendsACharge() {
        let level = TestLevels.make(prefilled: [(TestLevels.cell(1, 0), [.sky, .mint])], supply: [[.coral]], regions: [.violet])
        var engine = GameEngine(level: level)
        let events = engine.useHammer(at: TestLevels.cell(1, 0))
        #expect(events.first == .stackRemoved(cell: TestLevels.cell(1, 0), stack: TileStack([.sky, .mint])))
        #expect(engine.state.board.stack(at: TestLevels.cell(1, 0)) == nil)
        #expect(engine.state.boosters.hammer == 0)
        let outcome7 = engine.useHammer(at: TestLevels.cell(0, 1)).isEmpty
        #expect(outcome7)
    }

    @Test func hammerOnAnEmptyCellIsIgnored() {
        var engine = GameEngine(level: TestLevels.make(supply: [[.coral]], regions: [.violet]))
        let outcome8 = engine.useHammer(at: origin).isEmpty
        #expect(outcome8)
        #expect(engine.state.boosters.hammer == 1)
    }

    @Test func refreshSendsTheTrayToTheBackOfTheQueue() {
        let level = TestLevels.make(supply: [[.sky], [.mint], [.lemon], [.rose], [.indigo]], regions: [.violet])
        var engine = GameEngine(level: level)
        let events = engine.useRefresh()
        #expect(events == [.trayRefreshed(slots: [TileStack([.rose]), TileStack([.indigo]), TileStack([.sky])])])
        #expect(engine.state.queue == [TileStack([.mint]), TileStack([.lemon])])
        #expect(engine.state.boosters.refresh == 0)
    }

    @Test func refreshNeedsSomethingLeftToDeal() {
        let level = TestLevels.make(supply: [[.sky], [.mint]], regions: [.violet])
        var engine = GameEngine(level: level)
        #expect(!engine.canRefresh)
        let outcome9 = engine.useRefresh().isEmpty
        #expect(outcome9)
    }
}

@Suite("Save and restore")
struct SaveTests {
    private let origin = TestLevels.cell(0, 0)

    private func level() -> LevelDefinition {
        TestLevels.make(
            pencilSize: 3, prefilled: [(TestLevels.cell(1, 0), [.coral, .coral])],
            supply: [[.coral], [.sky, .mint], [.lemon], [.rose]], regions: [.coral, .sky], moveLimit: 6)
    }

    @Test func gameStateSurvivesAJSONRoundTrip() throws {
        var engine = GameEngine(level: level())
        engine.place(slot: 0, at: origin)
        let data = try JSONEncoder().encode(engine.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded == engine.state)
    }

    @Test func aRestoredGameContinuesExactlyLikeTheOriginal() throws {
        let storage = InMemorySaveStorage()
        var original = GameEngine(level: level())
        original.place(slot: 0, at: origin)
        SaveStore(storage: storage).saveInProgress(original)

        let reopened = SaveStore(storage: storage)
        var restored = try #require(reopened.restoreEngine(for: level()))
        #expect(restored.state == original.state)
        #expect(restored.undoHistory == original.undoHistory)

        let next = TestLevels.cell(-1, 1)
        let outcome10 = restored.place(slot: 1, at: next) == original.place(slot: 1, at: next)
        #expect(outcome10)
        #expect(restored.state == original.state)
        let outcome11 = restored.undo() == original.undo()
        #expect(outcome11)
        #expect(restored.state == original.state)
    }

    @Test func restoreIgnoresASaveForAnotherLevel() {
        let storage = InMemorySaveStorage()
        let engine = GameEngine(level: level())
        let store = SaveStore(storage: storage)
        var moved = engine
        moved.place(slot: 0, at: origin)
        store.saveInProgress(moved)
        let other = TestLevels.make(supply: [[.sky]], regions: [.violet])
        // The test levels share id 99, so compare through a different id.
        let renamed = LevelDefinition(
            id: 7, name: "Other", pencilSize: other.pencilSize, boardRadius: other.boardRadius,
            supply: other.supply, artwork: other.artwork)
        #expect(store.restoreEngine(for: renamed) == nil)
    }

    @Test func openingAnotherLevelDoesNotReplaceTheSavedGame() {
        let storage = InMemorySaveStorage()
        let store = SaveStore(storage: storage)
        var played = GameEngine(level: level())
        played.place(slot: 0, at: origin)
        store.saveInProgress(played)

        let other = TestLevels.make(supply: [[.sky], [.mint]], regions: [.violet])
        let otherLevel = LevelDefinition(
            id: 7, name: "Other", pencilSize: other.pencilSize, boardRadius: other.boardRadius,
            supply: other.supply, artwork: other.artwork)
        store.saveInProgress(GameEngine(level: otherLevel))   // untouched level: must not overwrite
        #expect(store.data.inProgress?.levelID == level().id)

        var movedOther = GameEngine(level: otherLevel)
        movedOther.place(slot: 0, at: origin)
        store.saveInProgress(movedOther)                       // a real move does take over the slot
        #expect(store.data.inProgress?.levelID == 7)
    }

    @Test func spendingABoosterAndUndoingToMoveZeroStillSavesTheRun() throws {
        let storage = InMemorySaveStorage()
        let store = SaveStore(storage: storage)
        var engine = GameEngine(level: level())
        let refreshed = !engine.useRefresh().isEmpty
        #expect(refreshed)
        let undone = engine.undo()
        #expect(undone)
        #expect(engine.state.movesUsed == 0 && engine.undoHistory.isEmpty)
        #expect(engine.boostersUsed == 1)
        store.saveInProgress(engine)
        let restored = try #require(store.restoreEngine(for: level()))
        #expect(restored.boostersUsed == 1)
    }

    @Test func anUnreadableSaveIsKeptAside() throws {
        let storage = InMemorySaveStorage()
        try storage.save(Data("{\"version\": 1, \"progress\": ".utf8))
        _ = SaveStore(storage: storage)
        #expect(storage.preservedUnreadable != nil)
    }

    @Test func aWrongTypedFieldDoesNotCostTheRestOfTheSave() throws {
        let storage = InMemorySaveStorage()
        try storage.save(Data("{\"version\": 1, \"progress\": 12, \"settings\": {\"tileSymbols\": true}}".utf8))
        let store = SaveStore(storage: storage)
        #expect(store.progress == PlayerProgress())
        #expect(store.settings.tileSymbols)
    }

    @Test func finishedGamesAreNotSavedAsInProgress() {
        let storage = InMemorySaveStorage()
        let store = SaveStore(storage: storage)
        var engine = GameEngine(level: TestLevels.make(supply: [[.sky]], regions: [.violet]))
        engine.place(slot: 0, at: origin)
        store.saveInProgress(engine)
        #expect(store.data.inProgress == nil)
    }

    @Test func winsKeepTheBestResultAndUnlockTheNextLevel() {
        let store = SaveStore(storage: InMemorySaveStorage())
        #expect(store.isUnlocked(1))
        #expect(!store.isUnlocked(2))
        store.recordWin(levelID: 1, nextLevelID: 2, stars: 2, score: 400)
        store.recordWin(levelID: 1, nextLevelID: 2, stars: 1, score: 900)
        #expect(store.isUnlocked(2))
        #expect(store.progress.bestStars[1] == 2)
        #expect(store.progress.bestScores[1] == 900)
    }

    @Test func progressAndSettingsPersistAcrossLaunches() {
        let storage = InMemorySaveStorage()
        let first = SaveStore(storage: storage)
        first.recordWin(levelID: 1, nextLevelID: 2, stars: 3, score: 700)
        first.updateSettings { $0.soundEnabled = false }
        let second = SaveStore(storage: storage)
        #expect(second.progress == first.progress)
        #expect(second.settings.soundEnabled == false)
        #expect(second.settings.hapticsEnabled == true)
    }

    @Test func aCorruptSaveFileStartsFresh() throws {
        let storage = InMemorySaveStorage()
        try storage.save(Data("not json".utf8))
        let store = SaveStore(storage: storage)
        #expect(store.progress == PlayerProgress())
        #expect(store.data.inProgress == nil)
    }

    @Test func fileStorageWritesAndReadsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pencil-hive-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileSaveStorage(url: directory.appendingPathComponent("nested/save.json"))
        #expect(try storage.load() == nil)
        let store = SaveStore(storage: storage)
        store.recordWin(levelID: 2, nextLevelID: 3, stars: 3, score: 1200)
        #expect(SaveStore(storage: storage).progress.bestScores[2] == 1200)
    }

    @Test func resettingProgressKeepsSettings() {
        let store = SaveStore(storage: InMemorySaveStorage())
        store.updateSettings { $0.hapticsEnabled = false }
        store.recordWin(levelID: 1, nextLevelID: 2, stars: 3, score: 500)
        store.resetAll()
        #expect(store.progress == PlayerProgress())
        #expect(store.settings.hapticsEnabled == false)
    }
}
