import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Cascades and pencils")
struct CascadeAndPencilTests {
    private let origin = TestLevels.cell(0, 0)

    @Test func revealedColourTriggersAChainedMatch() {
        // A lands on B and takes its coral; B is left showing sky, which touches C's sky.
        let b = TestLevels.cell(1, 0), c = TestLevels.cell(2, -1)
        let level = TestLevels.make(
            pencilSize: 6, prefilled: [(b, [.sky, .coral]), (c, [.sky])], supply: [[.coral]], regions: [.mint])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.transfers == [
            .tilesTransferred(from: b, to: origin, color: .coral, count: 1, chain: 0),
            .tilesTransferred(from: c, to: b, color: .sky, count: 1, chain: 1),
        ])
        #expect(engine.state.board.stack(at: origin) == TileStack([.coral, .coral]))
        #expect(engine.state.board.stack(at: b) == TileStack([.sky, .sky]))
        #expect(engine.state.board.stack(at: c) == nil)
        #expect(engine.state.bestChain == 1)
    }

    @Test func cascadesKeepGoingAcrossSeveralStacks() {
        let b = TestLevels.cell(1, 0), c = TestLevels.cell(2, -1), d = TestLevels.cell(2, -2)
        let level = TestLevels.make(
            pencilSize: 8,
            prefilled: [(b, [.sky, .coral]), (c, [.mint, .sky]), (d, [.mint])],
            supply: [[.coral]], regions: [.violet])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.transfers.count == 3)
        #expect(engine.state.bestChain == 2)
        #expect(engine.state.board.stack(at: c) == TileStack([.mint, .mint]))
        #expect(engine.state.board.stack(at: d) == nil)
    }

    @Test func boardIsStableAfterEveryResolvedMove() {
        let level = TestLevels.make(
            pencilSize: 6,
            prefilled: [(TestLevels.cell(1, 0), [.sky, .coral]), (TestLevels.cell(2, -1), [.sky])],
            supply: [[.coral]], regions: [.mint])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(engine.state.board.isStable)
    }

    @Test func reachingThePencilSizeClearsTheRunIntoAPencil() {
        let b = TestLevels.cell(1, 0)
        let level = TestLevels.make(pencilSize: 3, prefilled: [(b, [.coral, .coral])], supply: [[.coral]], regions: [.coral, .sky])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.pencils == [.pencilCompleted(cell: origin, color: .coral, tileCount: 3, regionID: 1, chain: 0)])
        #expect(engine.state.board.stack(at: origin) == nil)
        #expect(engine.state.pencilsByColor[.coral] == 1)
        #expect(engine.state.filledRegions == [1])
        // 2 moved tiles (20) + a pencil of 3 tiles (75).
        #expect(engine.state.score == 95)
    }

    @Test func aPlacedStackThatAlreadyFormsAPencilIsCleared() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral]], regions: [.coral, .sky])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.pencils.count == 1)
        #expect(engine.state.board.occupiedCells.isEmpty)
    }

    @Test func clearingAPencilRevealsTheColourBelowAndKeepsMatching() {
        let b = TestLevels.cell(1, 0), c = TestLevels.cell(0, 1)
        let level = TestLevels.make(
            pencilSize: 3,
            prefilled: [(b, [.coral, .coral]), (c, [.sky])],
            supply: [[.sky, .coral]], regions: [.coral, .sky])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.pencils.count == 1)
        // After the coral pencil the sky underneath touches C's sky and absorbs it at chain depth 1.
        #expect(events.transfers.last == .tilesTransferred(from: c, to: origin, color: .sky, count: 1, chain: 1))
        #expect(engine.state.board.stack(at: origin) == TileStack([.sky, .sky]))
    }

    @Test func longerRunsAreClearedWholeInOnePencil() {
        let level = TestLevels.make(pencilSize: 3, prefilled: [(TestLevels.cell(1, 0), [.coral, .coral])], supply: [[.coral, .coral]], regions: [.coral, .sky])
        var engine = GameEngine(level: level)
        let events = engine.place(slot: 0, at: origin)
        #expect(events.pencils == [.pencilCompleted(cell: origin, color: .coral, tileCount: 4, regionID: 1, chain: 0)])
        #expect(engine.state.pencilsByColor[.coral] == 1)
    }

    @Test func extraPencilsWithoutAMatchingRegionStillCount() {
        let level = TestLevels.make(pencilSize: 3, supply: [[.coral, .coral, .coral], [.coral, .coral, .coral]], regions: [.coral, .sky])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: origin)
        #expect(engine.state.pencilsByColor[.coral] == 1)
        engine.place(slot: 1, at: TestLevels.cell(1, 0))
        #expect(engine.state.pencilsByColor[.coral] == 2)
        #expect(engine.state.filledRegions == [1])
        // The second coral pencil has no region to fill, and the supply is now empty.
        #expect(engine.state.status == .failed(.outOfSupply))
    }
}
