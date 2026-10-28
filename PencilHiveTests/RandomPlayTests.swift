import Foundation
import Testing

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

/// Deterministic generator so a failing seed can be replayed.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("Random play")
struct RandomPlayTests {
    @Test func randomGamesAlwaysTerminateWithConsistentState() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        for level in library.levels {
            var wins = 0
            let games = 40
            for seed in 0..<games {
                var rng = SeededRandom(state: UInt64(seed + 1) &* 7919)
                var engine = GameEngine(level: level)
                var steps = 0
                while engine.state.status.isPlaying && steps < 500 {
                    let slots = engine.state.tray.indices.filter { engine.state.tray[$0] != nil }
                    let cells = engine.legalCells
                    guard let slot = slots.randomElement(using: &rng), let cell = cells.randomElement(using: &rng) else {
                        // A full board is not a loss while a hammer is left: smashing a stack is the way out.
                        guard engine.canHammer, let target = engine.state.board.occupiedCells.randomElement(using: &rng) else {
                            Issue.record("Level \(level.id) seed \(seed): playing with no legal move")
                            break
                        }
                        #expect(!engine.useHammer(at: target).isEmpty)
                        steps += 1
                        continue
                    }
                    #expect(!engine.place(slot: slot, at: cell).isEmpty)
                    for (_, stack) in engine.state.board.stacks { #expect(stack.height <= level.maxStackHeight) }
                    steps += 1
                }
                #expect(!engine.state.status.isPlaying, "Level \(level.id) seed \(seed) never ended")
                if case .won = engine.state.status { wins += 1 }
            }
            print("RANDOM-PLAY level \(level.id): \(wins)/\(games) wins")
        }
    }

    /// One-move lookahead: pick the placement that completes the most pencils, then scores most.
    /// Models a casual player who only looks at the immediate payoff.
    @Test func greedyGamesTerminateAndReportWinRate() throws {
        let library = try LevelLibrary.load(directory: TestLevels.levelsDirectory)
        for level in library.levels {
            var wins = 0
            let games = 20
            for seed in 0..<games {
                var rng = SeededRandom(state: UInt64(seed + 1) &* 104729)
                var engine = GameEngine(level: level)
                var steps = 0
                while engine.state.status.isPlaying && steps < 500 {
                    var best: (slot: Int, cell: HexCoord, value: Int)?
                    for slot in engine.state.tray.indices where engine.state.tray[slot] != nil {
                        for cell in engine.legalCells {
                            var trial = engine
                            _ = trial.place(slot: slot, at: cell)
                            let value = trial.state.pencilsCompleted * 100_000 + trial.state.score * 10 + Int.random(in: 0..<10, using: &rng)
                            if best == nil || value > best!.value { best = (slot, cell, value) }
                        }
                    }
                    if let move = best {
                        _ = engine.place(slot: move.slot, at: move.cell)
                    } else if engine.canHammer, let target = engine.state.board.occupiedCells.randomElement(using: &rng) {
                        _ = engine.useHammer(at: target)
                    } else {
                        Issue.record("Level \(level.id) greedy seed \(seed): no legal move while playing")
                        break
                    }
                    steps += 1
                }
                #expect(!engine.state.status.isPlaying, "Level \(level.id) greedy seed \(seed) never ended")
                if case .won = engine.state.status { wins += 1 }
            }
            print("GREEDY-PLAY level \(level.id): \(wins)/\(games) wins")
            if [2, 3, 4, 5, 7, 8].contains(level.id) {
                // These early difficulty spikes have recovery tiles after the original deal.
                // Keep the same seeded one-move policy so a future re-forge cannot silently
                // restore the old low win rates. This is not a human win-rate claim.
                #expect(wins >= games / 2, "Level \(level.id) is too brittle for immediate-match play")
            }
        }
    }
}
