import Foundation

/// Depth-first search over placements. Used by tests and the level tool to prove a level can be
/// won without boosters; it is not part of normal play.
struct Solver {
    struct Move: Equatable {
        let stack: TileStack
        let cell: HexCoord
    }

    struct Result {
        let moves: [Move]?
        let nodesVisited: Int
        let exhausted: Bool
        var isSolvable: Bool { moves != nil }
    }

    let level: LevelDefinition
    let nodeLimit: Int

    init(level: LevelDefinition, nodeLimit: Int = 2_000_000) {
        self.level = level
        self.nodeLimit = nodeLimit
    }

    /// Finds a win without boosters. With `goal`, only a win that also meets the level's star goal
    /// counts, which proves the second star can actually be earned.
    func solve(requiring goal: StarGoal? = nil) -> Result {
        var visited = Set<String>()
        var nodes = 0
        var path: [Move] = []

        func search(_ engine: GameEngine) -> Bool {
            if case .won = engine.state.status { return goal.map { $0.isMet(by: engine.state) } ?? true }
            guard engine.state.status.isPlaying else { return false }
            if case .stacks(let limit)? = goal, engine.state.movesUsed >= limit { return false }
            nodes += 1
            if nodes > nodeLimit { return false }
            guard visited.insert(key(of: engine, goal: goal)).inserted else { return false }
            guard canStillWin(engine) else { return false }

            var candidates: [(engine: GameEngine, move: Move, rank: Int)] = []
            var seenStacks = Set<TileStack>()
            for slot in engine.state.tray.indices {
                guard let stack = engine.state.tray[slot], seenStacks.insert(stack).inserted else { continue }
                for cell in engine.legalCells {
                    var next = engine
                    next.place(slot: slot, at: cell)
                    var rank = next.state.filledRegions.count * 10_000 - next.state.board.tileCount * 10 + next.state.score / 10
                    switch goal {
                    case .chain(let depth)?: rank += min(next.state.bestChain + 1, depth) * 50_000
                    case .score?: rank += next.state.score * 20
                    default: break
                    }
                    candidates.append((next, Move(stack: stack, cell: cell), rank))
                }
            }
            candidates.sort { $0.rank > $1.rank }
            for candidate in candidates {
                path.append(candidate.move)
                if search(candidate.engine) { return true }
                path.removeLast()
                if nodes > nodeLimit { return false }
            }
            return false
        }

        let solved = search(GameEngine(level: level))
        return Result(moves: solved ? path : nil, nodesVisited: nodes, exhausted: nodes <= nodeLimit)
    }

    /// Cheap pruning: every colour still needs enough tiles left on the board and in supply.
    private func canStillWin(_ engine: GameEngine) -> Bool {
        var available = engine.state.board.colorCounts
        for stack in engine.state.tray.compactMap({ $0 }) + engine.state.queue {
            for (color, count) in stack.colorCounts { available[color, default: 0] += count }
        }
        for (color, regions) in engine.remainingGoals where available[color, default: 0] < regions * level.pencilSize {
            return false
        }
        return true
    }

    private func key(of engine: GameEngine, goal: StarGoal?) -> String {
        // Two routes to the same position differ for a goal that depends on how it was reached.
        var history = ""
        switch goal {
        case .chain?: history = "|c\(engine.state.bestChain)"
        case .score?: history = "|s\(engine.state.score)"
        default: break
        }
        let tray = engine.state.trayStacks.map { $0.tiles.map { String($0.rawValue.prefix(2)) }.joined() }.sorted().joined(separator: ",")
        return "\(engine.state.board.signature)|\(tray)|\(engine.state.queue.count)|\(engine.state.movesUsed)\(history)"
    }
}
