import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Level data")
struct LevelTests {
    #if !canImport(PencilHiveCore)
    @Test func iOSTestsUseTheSamePackagedLevelsAsTheApp() throws {
        #expect(TestLevels.levelsDirectory.path.hasPrefix(Bundle.main.bundlePath + "/"))
        let packaged = try LevelLibrary.bundled()
        let tested = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        #expect(tested.levels == packaged.levels)
    }
    #endif

    @Test func shippedLevelsLoadAndValidate() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        #expect(library.levels.count >= 3)
        #expect(library.levels.map(\.id) == Array(1...library.levels.count))
    }

    @Test func shippedLevelsAreSolvableWithoutBoosters() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        for level in library.levels {
            let result = Solver(level: level, nodeLimit: 400_000).solve()
            #expect(result.isSolvable, "Level \(level.id) could not be solved (\(result.nodesVisited) nodes searched)")
        }
    }

    @Test func solverSolutionsReplayToAWin() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        for level in library.levels {
            let moves = try #require(Solver(level: level, nodeLimit: 400_000).solve().moves)
            var engine = GameEngine(level: level)
            for move in moves {
                let slot = try #require(engine.state.tray.firstIndex { $0 == move.stack })
                let outcome1 = !engine.place(slot: slot, at: move.cell).isEmpty
                #expect(outcome1)
            }
            if case .won = engine.state.status {} else { Issue.record("Level \(level.id) replay ended as \(engine.state.status)") }
        }
    }

    @Test func shippedLevelsCarryEnoughTilesForEveryColour() throws {
        for level in try LevelLibrary.load(directory: TestLevels.levelsDirectory).levels {
            for (color, regions) in level.goals {
                #expect(level.tileBudget[color, default: 0] >= regions * level.pencilSize)
            }
        }
    }

    @Test func everyLevelsStarGoalCanActuallyBeEarned() throws {
        // A goal nobody can reach would silently cap the level at two stars.
        for level in try LevelLibrary.load(directory: TestLevels.levelsDirectory).levels {
            let result = Solver(level: level, nodeLimit: 400_000).solve(requiring: level.starGoal)
            #expect(result.isSolvable, "Level \(level.id): the goal \"\(level.starGoal.summary)\" was not reached (\(result.nodesVisited) nodes)")
        }
    }

    @Test func theFirstSolutionTheSolverFindsDoesNotAlwaysCollectEveryStar() throws {
        // At least one level's goal must ask for more than the solver's default line gives.
        var someGoalNeedsExtraSkill = false
        for level in try LevelLibrary.load(directory: TestLevels.levelsDirectory).levels {
            let moves = try #require(Solver(level: level, nodeLimit: 400_000).solve().moves)
            var engine = GameEngine(level: level)
            for move in moves { engine.place(slot: try #require(engine.state.tray.firstIndex { $0 == move.stack }), at: move.cell) }
            if !engine.starReport.goalMet { someGoalNeedsExtraSkill = true }
        }
        #expect(someGoalNeedsExtraSkill)
    }

    @Test func theFirstTenLevelsAreForgiving() throws {
        // Casual players get generous boosters and a board with room to spare on levels 1-10.
        for level in try LevelLibrary.load(directory: TestLevels.levelsDirectory).levels where level.id <= 10 {
            #expect(level.boosters.undo >= 5, "Level \(level.id) should give at least 5 undos")
            #expect(level.boosters.hammer >= 1, "Level \(level.id) should give a hammer")
            #expect(level.cells.count >= 16, "Level \(level.id) board is too tight for a casual level")
        }
    }

    @Test func moveLimitsNeverExceedTheSupply() throws {
        // A limit above the number of stacks could never bind and would only add a free bonus.
        for level in try LevelLibrary.load(directory: TestLevels.levelsDirectory).levels {
            if let limit = level.moveLimit { #expect(limit <= level.supply.count) }
        }
    }

    @Test func rocketCanRecoverFromTheManualSkyDeadEnd() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        let level = try #require(library.level(id: 3))
        var engine = GameEngine(level: level)
        // Replays the simulator touch session: all but sky finished in the original 12 moves.
        let route: [(Int, Int, Int)] = [
            (0, 0, -1), (1, -1, 1), (2, 0, 0),
            (2, 0, 1), (1, -1, 2), (0, -1, 1),
            (0, 0, 0), (1, 1, 0), (2, -2, 2),
            (0, -1, 0), (2, 0, 0), (1, 0, -1),
        ]
        for (slot, q, r) in route {
            #expect(!engine.place(slot: slot, at: HexCoord(q: q, r: r)).isEmpty)
        }
        #expect(engine.state.filledRegions.count == 8)
        #expect(engine.remainingGoals == [.sky: 1])
        #expect(engine.state.status.isPlaying)
        let slot = try #require(engine.state.tray.firstIndex { $0 == TileStack([.sky]) })
        // The spare single completes the isolated sky triple without a booster or a restart.
        #expect(!engine.place(slot: slot, at: HexCoord(q: -2, r: 1)).isEmpty)
        if case .won = engine.state.status {} else { Issue.record("Sky recovery should finish level 3") }
        #expect(engine.starReport.boosterFree)
    }

    @Test func meadowAndTreeCanRecoverFromManualDeadEnds() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        let routes: [(Int, [(Int, Int, Int)], [(Int, Int, Int)])] = [
            (5, [
                (0, 0, -1), (1, 0, 0), (2, -1, 0),
                (0, -1, 2), (1, 1, 0), (2, 1, 1),
                (0, 0, -1), (1, 1, -1), (2, -1, -1),
                (0, 1, 0), (1, 0, 1), (2, -1, 1),
            ], [(0, -1, 0)]),
            (8, [
                (0, 1, 0), (1, 0, 2), (2, -2, 1), (0, 0, -1),
            ], [(1, -2, 0), (2, 0, 0)]),
        ]
        for (id, opening, recovery) in routes {
            var engine = GameEngine(level: try #require(library.level(id: id)))
            for (slot, q, r) in opening {
                #expect(!engine.place(slot: slot, at: HexCoord(q: q, r: r)).isEmpty)
            }
            #expect(engine.state.status.isPlaying, "Level \(id) should offer recovery after the original supply")
            #expect(!engine.remainingGoals.isEmpty)
            for (slot, q, r) in recovery {
                if case .won = engine.state.status { break }
                #expect(!engine.place(slot: slot, at: HexCoord(q: q, r: r)).isEmpty)
            }
            if case .won = engine.state.status {} else { Issue.record("Level \(id) recovery should finish the picture") }
            #expect(engine.starReport.boosterFree)
        }
    }

    @Test func levelsRoundTripThroughJSON() throws {
        for level in try LevelLibrary.load(directory: TestLevels.levelsDirectory).levels {
            let data = try JSONEncoder().encode(level)
            #expect(try JSONDecoder().decode(LevelDefinition.self, from: data) == level)
        }
    }

    @Test func solverReportsUnsolvableLevels() {
        // Only one stack of the needed colour exists, so no pencil can ever form.
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral], [.sky]], regions: [.coral])
        #expect(!Solver(level: level).solve().isSolvable)
    }

    @Test func validatorFlagsBrokenLevels() {
        let tooFewTiles = TestLevels.make(pencilSize: 3, supply: [[.coral]], regions: [.coral])
        #expect(!LevelValidator.validate(tooFewTiles).isEmpty)

        let alreadyAPencil = TestLevels.make(
            pencilSize: 3, prefilled: [(TestLevels.cell(0, 0), [.coral, .coral, .coral])], supply: [[.coral, .coral, .coral]], regions: [.coral])
        #expect(LevelValidator.validate(alreadyAPencil).contains { $0.contains("already a pencil") })

        let unstable = TestLevels.make(
            pencilSize: 3,
            prefilled: [(TestLevels.cell(0, 0), [.coral]), (TestLevels.cell(1, 0), [.coral])],
            supply: [[.coral, .coral, .coral]], regions: [.coral])
        #expect(LevelValidator.validate(unstable).contains { $0.contains("same top colour") })

        let offBoard = TestLevels.make(prefilled: [(TestLevels.cell(9, 9), [.sky])], supply: [[.coral, .coral, .coral]], regions: [.coral])
        #expect(LevelValidator.validate(offBoard).contains { $0.contains("not on the board") })
    }

    @Test func aGoodHandMadeLevelPassesValidation() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral], [.coral]], regions: [.coral])
        #expect(LevelValidator.validate(level).isEmpty)
    }

    @Test func libraryRejectsDuplicateIds() throws {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral], [.coral]], regions: [.coral])
        let data = try JSONEncoder().encode(level)
        #expect(throws: LevelLibraryError.self) { try LevelLibrary.decode([data, data]) }
    }

    @Test func libraryProvidesNextLevelLookup() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        #expect(library.level(after: 1)?.id == 2)
        #expect(library.level(after: library.levels.last!.id) == nil)
    }
}
