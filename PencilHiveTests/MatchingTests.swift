import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Matching and merging")
struct MatchingTests {
    private let origin = TestLevels.cell(0, 0)

    @Test func adjacentStacksWithTheSameTopColourMerge() {
        let level = TestLevels.make(pencilSize: 4, prefilled: [(TestLevels.cell(1, 0), [.sky])], supply: [[.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.transfers == [.tilesTransferred(from: TestLevels.cell(1, 0), to: origin, color: .sky, count: 1, chain: 0)])
        #expect(engine.state.board.stack(at: origin) == TileStack([.sky, .sky]))
        #expect(engine.state.board.stack(at: TestLevels.cell(1, 0)) == nil)
        #expect(engine.state.score == 10)
    }

    @Test func differentTopColoursDoNotMerge() {
        let level = TestLevels.make(pencilSize: 4, prefilled: [(TestLevels.cell(1, 0), [.mint])], supply: [[.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.transfers.isEmpty)
        #expect(engine.state.board.stack(at: TestLevels.cell(1, 0)) == TileStack([.mint]))
    }

    @Test func onlyTheTopRunMovesAndTheStackBelowIsRevealed() {
        let level = TestLevels.make(
            pencilSize: 5, prefilled: [(TestLevels.cell(1, 0), [.mint, .sky, .sky])], supply: [[.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(engine.state.board.stack(at: origin) == TileStack([.sky, .sky, .sky]))
        #expect(engine.state.board.stack(at: TestLevels.cell(1, 0)) == TileStack([.mint]))
    }

    @Test func nonAdjacentStacksNeverMerge() {
        let level = TestLevels.make(pencilSize: 4, prefilled: [(TestLevels.cell(2, 0), [.sky])], supply: [[.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        let outcome12 = engine.place(slot: 0, at: origin).transfers.isEmpty
        #expect(outcome12)
    }

    @Test func placedStackPullsFromEveryMatchingNeighbour() {
        let level = TestLevels.make(
            pencilSize: 6,
            prefilled: [(TestLevels.cell(1, 0), [.sky]), (TestLevels.cell(-1, 0), [.sky]), (TestLevels.cell(0, 1), [.mint])],
            supply: [[.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.transfers.count == 2)
        #expect(engine.state.board.stack(at: origin)?.height == 3)
        #expect(engine.state.board.stack(at: TestLevels.cell(0, 1)) == TileStack([.mint]))
    }

    @Test func neighboursAreResolvedInAFixedOrder() {
        let level = TestLevels.make(
            pencilSize: 6,
            prefilled: [(TestLevels.cell(-1, 0), [.sky]), (TestLevels.cell(1, 0), [.sky])],
            supply: [[.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        let froms = engine.place(slot: 0, at: origin).transfers.compactMap { event -> HexCoord? in
            if case .tilesTransferred(let from, _, _, _, _) = event { return from }
            return nil
        }
        #expect(froms == [TestLevels.cell(1, 0), TestLevels.cell(-1, 0)])
    }

    @Test func mergeIsSkippedWhenNeitherDirectionFitsUnderTheMaximumStackHeight() {
        let level = TestLevels.make(
            pencilSize: 5, prefilled: [(TestLevels.cell(1, 0), [.mint, .sky, .sky])], supply: [[.mint, .sky, .sky]],
            regions: [.coral], maxStackHeight: 4)
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.transfers.isEmpty)
        #expect(engine.state.board.stack(at: origin)?.height == 3)
    }

    @Test func scoreCountsTenPointsPerMovedTile() {
        let level = TestLevels.make(pencilSize: 6, prefilled: [(TestLevels.cell(1, 0), [.sky, .sky, .sky])], supply: [[.sky]], regions: [.coral])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(engine.state.score == 30)
    }
}
