import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Goals, win and fail")
struct GoalAndStatusTests {
    private let origin = TestLevels.cell(0, 0)

    @Test func goalsComeFromTheArtworkRegions() {
        let level = TestLevels.make(regions: [.coral, .coral, .sky])
        #expect(level.goals == [.coral: 2, .sky: 1])
        #expect(level.totalPencilsNeeded == 3)
        #expect(GameEngine(level: level).remainingGoals == [.coral: 2, .sky: 1])
    }

    @Test func finishingThePictureWinsTheLevel() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral]], regions: [.coral], starGoal: .score(20))
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.last == .levelCompleted(stars: 3))
        #expect(engine.state.status == .won(stars: 3))
        #expect(engine.remainingGoals.isEmpty)
    }

    @Test func aCleanWinThatMeetsTheGoalEarnsThreeStars() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral]], regions: [.coral], starGoal: .score(50))
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(engine.starReport == StarReport(goalMet: true, boosterFree: true))
        #expect(engine.state.status == .won(stars: 3))
    }

    @Test func missingTheGoalCostsOneStar() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral]], regions: [.coral], starGoal: .score(10_000))
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(engine.starReport == StarReport(goalMet: false, boosterFree: true))
        #expect(engine.state.status == .won(stars: 2))
    }

    @Test func spendingAnyBoosterCostsOneStarEvenIfItIsUndone() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.sky], [.coral, .coral, .coral]], regions: [.coral], starGoal: .score(50))
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        _ = engine.undo()
        #expect(engine.boostersUsed == 1)
        engine.placeStack([.coral, .coral, .coral], at: origin)
        #expect(engine.starReport == StarReport(goalMet: true, boosterFree: false))
        #expect(engine.state.status == .won(stars: 2))
    }

    @Test func missingBothBonusesStillEarnsOneStar() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.sky], [.coral, .coral, .coral]], regions: [.coral], starGoal: .score(10_000))
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        _ = engine.undo()
        engine.placeStack([.coral, .coral, .coral], at: origin)
        #expect(engine.state.status == .won(stars: 1))
    }

    @Test func eachKindOfGoalIsJudgedOnTheFinishedRun() {
        var state = GameEngine(level: TestLevels.make()).state
        state.bestChain = 2          // the third link of a chain, shown as x3
        state.movesUsed = 7
        state.score = 900
        #expect(StarGoal.chain(3).isMet(by: state))
        #expect(!StarGoal.chain(4).isMet(by: state))
        #expect(StarGoal.stacks(7).isMet(by: state))
        #expect(!StarGoal.stacks(6).isMet(by: state))
        #expect(StarGoal.score(900).isMet(by: state))
        #expect(!StarGoal.score(901).isMet(by: state))
        #expect(StarGoal.none.isMet(by: state))
    }

    @Test func starGoalsRoundTripThroughJSON() throws {
        for goal in [StarGoal.chain(4), .stacks(7), .score(1760)] {
            let data = try JSONEncoder().encode(goal)
            #expect(try JSONDecoder().decode(StarGoal.self, from: data) == goal)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StarGoal.self, from: Data(#"{"kind": "speed", "value": 3}"#.utf8))
        }
    }

    @Test func aLevelWithoutAGoalStillLoadsAndAlwaysMeetsIt() throws {
        let level = TestLevels.make(supply: [[.coral, .coral, .coral]], regions: [.coral])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(level)) as? [String: Any])
        object["starGoal"] = nil
        let decoded = try JSONDecoder().decode(LevelDefinition.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.starGoal == .none)
    }

    @Test func unusedMovesAddABonusOnWin() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral]], regions: [.coral], moveLimit: 5)
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        // 3 tiles x 25 points + 4 unused moves x 50.
        #expect(engine.state.score == 75 + 4 * GameEngine.leftoverMovePoints)
    }

    @Test func movesRemainingCountsDown() {
        let level = TestLevels.make(supply: [[.sky], [.mint], [.lemon]], regions: [.violet], moveLimit: 3)
        var engine = GameEngine(level: level)
        #expect(engine.movesRemaining == 3)
        engine.place(slot: 0, at: TestLevels.cell(-2, 0))
        #expect(engine.movesRemaining == 2)
    }

    @Test func runningOutOfMovesFailsTheLevel() {
        let level = TestLevels.make(supply: [[.sky], [.mint], [.lemon]], regions: [.violet], moveLimit: 1)
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.last == .levelFailed(reason: .outOfMoves))
        #expect(engine.state.status == .failed(.outOfMoves))
    }

    @Test func winningOnTheLastMoveBeatsFailing() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral]], regions: [.coral], moveLimit: 1)
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        if case .won = engine.state.status {} else { Issue.record("expected a win, got \(engine.state.status)") }
    }

    /// Ring of six alternating stacks around an empty centre, so nothing ever matches.
    private func fullBoardLevel(boosters: BoosterInventory) -> LevelDefinition {
        let ring = HexCoord.directions.enumerated().map { ($0.element, [$0.offset % 2 == 0 ? TileColor.coral : TileColor.sky]) }
        return TestLevels.make(
            pencilSize: 4, radius: 1, prefilled: ring, supply: [[.mint], [.lemon]], regions: [.violet], boosters: boosters)
    }

    @Test func aFullBoardWithStacksWaitingFailsTheLevel() {
        var engine = GameEngine(level: fullBoardLevel(boosters: BoosterInventory(undo: 1)))
        let events = engine.place(slot: 0, at: origin)
        #expect(events.last == .levelFailed(reason: .boardFull))
    }

    @Test func aHammerKeepsAFullBoardPlayable() {
        var engine = GameEngine(level: fullBoardLevel(boosters: BoosterInventory(hammer: 1)))
        engine.place(slot: 0, at: origin)
        #expect(engine.state.status == .playing)
        engine.useHammer(at: TestLevels.cell(1, 0))
        #expect(engine.legalCells == [TestLevels.cell(1, 0)])
        #expect(engine.state.status == .playing)
    }

    @Test func nothingHappensAfterTheGameEnded() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral], [.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        let frozen = engine.state
        let outcome13 = engine.place(slot: 1, at: TestLevels.cell(1, 0)).isEmpty
        #expect(outcome13)
        let outcome14 = engine.useHammer(at: origin).isEmpty
        #expect(outcome14)
        #expect(engine.state == frozen)
    }
}
