import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

@Suite("Placement")
struct PlacementTests {
    @Test func initialStateDealsTheTray() {
        let level = TestLevels.make(supply: [[.coral], [.sky], [.mint], [.lemon]])
        let engine = GameEngine(level: level)
        #expect(engine.state.tray.compactMap { $0 }.count == 3)
        #expect(engine.state.queue == [TileStack([.lemon])])
        #expect(engine.state.movesUsed == 0)
        #expect(engine.state.status == .playing)
    }

    @Test func placingOnAnEmptyCellMovesTheStackOntoTheBoard() {
        var engine = GameEngine(level: TestLevels.make(supply: [[.sky, .mint]]))
        let events = engine.place(slot: 0, at: TestLevels.cell(0, 0))
        #expect(events.first == .stackPlaced(slot: 0, cell: TestLevels.cell(0, 0), stack: TileStack([.sky, .mint])))
        #expect(engine.state.board.stack(at: TestLevels.cell(0, 0)) == TileStack([.sky, .mint]))
        #expect(engine.state.tray[0] == nil)
        #expect(engine.state.movesUsed == 1)
    }

    @Test func cannotPlaceOnAnOccupiedCell() {
        let level = TestLevels.make(prefilled: [(TestLevels.cell(0, 0), [.sky])], supply: [[.mint]])
        var engine = GameEngine(level: level)
        #expect(!engine.canPlace(slot: 0, at: TestLevels.cell(0, 0)))
        let outcome15 = engine.place(slot: 0, at: TestLevels.cell(0, 0)).isEmpty
        #expect(outcome15)
        #expect(engine.state.movesUsed == 0)
        #expect(engine.state.tray[0] != nil)
    }

    @Test func cannotPlaceOffTheBoardOrInAnEmptySlot() {
        var engine = GameEngine(level: TestLevels.make(radius: 1, supply: [[.mint]]))
        #expect(!engine.canPlace(slot: 0, at: TestLevels.cell(3, 0)))
        #expect(!engine.canPlace(slot: 1, at: TestLevels.cell(0, 0)))
        #expect(!engine.canPlace(slot: 7, at: TestLevels.cell(0, 0)))
        let outcome16 = engine.place(slot: 0, at: TestLevels.cell(3, 0)).isEmpty
        #expect(outcome16)
    }

    @Test func removedCellsAreNotPartOfTheBoard() {
        let level = TestLevels.make(radius: 1, removed: [TestLevels.cell(1, 0)], supply: [[.mint]])
        let engine = GameEngine(level: level)
        #expect(engine.legalCells.count == 6)
        #expect(!engine.legalCells.contains(TestLevels.cell(1, 0)))
    }

    @Test func trayRefillsOnlyWhenEveryStackWasPlaced() {
        let level = TestLevels.make(supply: [[.sky], [.mint], [.lemon], [.rose], [.violet]], regions: [.indigo])
        var engine = GameEngine(level: level)
        engine.place(slot: 0, at: TestLevels.cell(-2, 0))
        engine.place(slot: 1, at: TestLevels.cell(0, -2))
        #expect(engine.state.tray.compactMap { $0 }.count == 1)
        let events = engine.place(slot: 2, at: TestLevels.cell(2, 0))
        let refill = events.compactMap { event -> [TileStack?]? in
            if case .trayRefilled(let slots) = event { return slots }
            return nil
        }.first
        #expect(refill == [TileStack([.rose]), TileStack([.violet]), nil])
        #expect(engine.state.queue.isEmpty)
    }

    @Test func gameEndsWhenNoStacksRemain() {
        var engine = GameEngine(level: TestLevels.make(supply: [[.sky]], regions: [.mint]))
        let events = engine.place(slot: 0, at: TestLevels.cell(0, 0))
        #expect(events.last == .levelFailed(reason: .outOfSupply))
        #expect(engine.state.status == .failed(.outOfSupply))
        let outcome17 = engine.place(slot: 0, at: TestLevels.cell(1, 0)).isEmpty
        #expect(outcome17)
    }
}
