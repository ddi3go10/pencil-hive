import CoreGraphics
import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

/// Each test replays an input that crashed or misbehaved during fuzzing of the data and save code.
@Suite("Fuzz regressions")
struct FuzzRegressionTests {
    private func levelJSON() throws -> [String: Any] {
        let url = TestLevels.levelsDirectory.appendingPathComponent("level_01.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> LevelLibrary {
        try LevelLibrary.decode([JSONSerialization.data(withJSONObject: json)])
    }

    // MARK: Level files

    @Test(arguments: [
        ("boardRadius", Int.max), ("boardRadius", 1_000_000), ("pencilSize", Int.max), ("pencilSize", Int.min),
        ("maxStackHeight", Int.max), ("trayCount", Int.max), ("moveLimit", Int.max), ("moveLimit", 5_000),
    ])
    func absurdNumbersAreRejectedNotTrapped(key: String, value: Int) throws {
        var json = try levelJSON()
        json[key] = value
        #expect(throws: LevelLibraryError.self) { try decode(json) }
    }

    @Test func hugeBoosterCountsAreRejected() throws {
        var json = try levelJSON()
        json["boosters"] = ["undo": Int.max, "hammer": 1, "refresh": 0]
        #expect(throws: LevelLibraryError.self) { try decode(json) }
    }

    @Test func prefilledCellsFarOffTheBoardAreRejected() throws {
        var json = try levelJSON()
        json["prefilled"] = [["cell": [Int.max, 0], "stack": ["sky"]]]
        #expect(throws: LevelLibraryError.self) { try decode(json) }
    }

    @Test func aBigButLegalRadiusStillValidatesQuickly() throws {
        var json = try levelJSON()
        json["boardRadius"] = 20
        let started = Date()
        _ = try? decode(json)   // may be invalid for other reasons; it only has to return fast
        #expect(Date().timeIntervalSince(started) < 2)
    }

    // MARK: Save files

    private func store(holding raw: String) throws -> SaveStore {
        let storage = InMemorySaveStorage()
        try storage.save(Data(raw.utf8))
        return SaveStore(storage: storage)
    }

    @Test func oneWrongTypedSettingKeepsTheRestOfTheSave() throws {
        let store = try store(holding: """
        {"version": 1.5, "progress": {"unlockedLevel": 3, "bestStars": {"1": 3}, "bestScores": {"1": 900}},
         "settings": {"soundEnabled": "yes", "hapticsEnabled": false}}
        """)
        #expect(store.progress.unlockedLevel == 3)
        #expect(store.progress.bestStars[1] == 3)
        #expect(store.settings.soundEnabled == true)     // the damaged field falls back to its default
        #expect(store.settings.hapticsEnabled == false)  // its neighbour survives
    }

    @Test func aWrongTypedProgressBlockDoesNotThrowAwayTheSettings() throws {
        let store = try store(holding: #"{"progress": 12, "settings": {"hapticsEnabled": false}}"#)
        #expect(store.progress == PlayerProgress())
        #expect(store.settings.hapticsEnabled == false)
    }

    @Test func aNonPositiveUnlockedLevelStillOpensLevelOne() throws {
        let store = try store(holding: #"{"progress": {"unlockedLevel": -4}}"#)
        #expect(store.isUnlocked(1))
        #expect(!store.isUnlocked(2))
    }

    @Test func absurdCountersInASavedGameAreRefusedNotPlayed() throws {
        let level = TestLevels.make(supply: [[.sky], [.mint], [.lemon]], regions: [.violet])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: TestLevels.cell(0, 0))

        func restored(_ damage: (inout GameState) -> Void) throws -> GameEngine? {
            var state = engine.state
            damage(&state)
            let storage = InMemorySaveStorage()
            let writer = SaveStore(storage: storage)
            writer.saveInProgress(GameEngine(level: level, state: state, history: [engine.state]))
            return SaveStore(storage: storage).restoreEngine(for: level)
        }

        #expect(try restored { $0.movesUsed = Int.max } == nil)
        #expect(try restored { $0.score = Int.max } == nil)
        #expect(try restored { $0.boosters.undo = Int.max } == nil)
        #expect(try restored { $0.pencilsByColor[.sky] = Int.max } == nil)
        #expect(try restored { $0.bestChain = Int.max } == nil)
        // An ordinary save still restores.
        #expect(try restored { _ in } != nil)
    }

    // MARK: Geometry

    @Test func layoutNeverTrapsOnOddInput() {
        let layout = HexLayout(size: 30)
        for point in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity), CGPoint(x: 1e300, y: 1e300), CGPoint(x: -1e300, y: 5)] {
            _ = layout.cell(at: point)
        }
        _ = HexLayout(size: 0).cell(at: CGPoint(x: 10, y: 10))
        _ = HexLayout(size: -5).cell(at: CGPoint(x: 10, y: 10))
        _ = HexLayout(size: CGFloat.nan).cell(at: CGPoint(x: 10, y: 10))
    }
}
