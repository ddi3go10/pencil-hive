import Foundation

/// The deterministic puzzle rules. No rendering, timing or randomness lives here.
///
/// Matching rule: after a stack lands on a cell, that stack looks at its six neighbours. Every
/// neighbour whose top colour equals its own gives its whole top run to it. A neighbour that is
/// left with a new top colour is checked in turn (a cascade). Whenever a stack's top run reaches
/// `pencilSize`, the run is cleared into a pencil, which exposes the colour underneath and may
/// trigger further matches.
/// Which of the three star conditions a finished level met.
struct StarReport: Equatable {
    var goalMet: Bool
    var boosterFree: Bool
    var stars: Int { 1 + (goalMet ? 1 : 0) + (boosterFree ? 1 : 0) }
}

struct GameEngine {
    /// Per-tile score for tiles that move between stacks.
    static let transferPoints = 10
    /// Per-tile score for tiles that become a pencil (multiplied by the chain depth).
    static let pencilPoints = 25
    /// Bonus per unused move when a level with a move limit is won.
    static let leftoverMovePoints = 50
    private static let historyLimit = 32

    let level: LevelDefinition
    private(set) var state: GameState
    private var history: [GameState] = []

    init(level: LevelDefinition) {
        self.level = level
        var queue = level.supply
        var tray: [TileStack?] = []
        for _ in 0..<level.trayCount {
            tray.append(queue.isEmpty ? nil : queue.removeFirst())
        }
        state = GameState(board: level.makeInitialBoard(), tray: tray, queue: queue, boosters: level.boosters)
    }

    /// Rebuilds an engine from a save file.
    init(level: LevelDefinition, state: GameState, history: [GameState] = []) {
        self.level = level
        self.state = state
        self.history = history
    }

    // MARK: Queries

    var undoHistory: [GameState] { history }
    var movesRemaining: Int? { level.moveLimit.map { max(0, $0 - state.movesUsed) } }
    /// Undo is allowed while playing and after a fail (to rescue the level), never after a win.
    var canUndo: Bool {
        if case .won = state.status { return false }
        return !history.isEmpty && state.boosters.undo > 0
    }
    var canRefresh: Bool { state.status.isPlaying && state.boosters.refresh > 0 && !state.queue.isEmpty && !state.trayIsEmpty }
    var canHammer: Bool { state.status.isPlaying && state.boosters.hammer > 0 && !state.board.occupiedCells.isEmpty }

    /// Pencils still needed of each colour.
    var remainingGoals: [TileColor: Int] {
        var goals = level.goals
        for id in state.filledRegions {
            if let region = level.artwork.region(id: id) { goals[region.color, default: 0] -= 1 }
        }
        return goals.filter { $0.value > 0 }
    }

    var legalCells: [HexCoord] { state.board.emptyCells }

    func canPlace(slot: Int, at cell: HexCoord) -> Bool {
        state.status.isPlaying
            && state.tray.indices.contains(slot)
            && state.tray[slot] != nil
            && state.board.isEmpty(cell)
    }

    // MARK: Moves

    /// Places the tray stack in `slot` on `cell`, resolves every match, and returns what happened.
    /// An illegal request changes nothing and returns `[]`.
    @discardableResult
    mutating func place(slot: Int, at cell: HexCoord) -> [GameEvent] {
        guard canPlace(slot: slot, at: cell), let stack = state.tray[slot] else { return [] }
        pushHistory()
        state.board.setStack(stack, at: cell)
        state.tray[slot] = nil
        state.movesUsed += 1

        var events: [GameEvent] = [.stackPlaced(slot: slot, cell: cell, stack: stack)]
        events += resolve(from: cell)

        if state.trayIsEmpty, !state.queue.isEmpty {
            dealTray()
            events.append(.trayRefilled(slots: state.tray))
        }
        events += evaluateStatus()
        return events
    }

    /// Booster: smash the stack on `cell`.
    @discardableResult
    mutating func useHammer(at cell: HexCoord) -> [GameEvent] {
        guard canHammer, let removed = state.board.stack(at: cell) else { return [] }
        pushHistory()
        _ = state.board.removeStack(at: cell)
        state.boosters.hammer -= 1
        return [.stackRemoved(cell: cell, stack: removed)] + evaluateStatus()
    }

    /// Booster: send the current tray to the back of the queue and deal fresh stacks.
    @discardableResult
    mutating func useRefresh() -> [GameEvent] {
        guard canRefresh else { return [] }
        pushHistory()
        state.queue.append(contentsOf: state.trayStacks)
        state.tray = Array(repeating: nil, count: level.trayCount)
        dealTray()
        state.boosters.refresh -= 1
        return [.trayRefreshed(slots: state.tray)] + evaluateStatus()
    }

    /// Booster: take back the last action (a placement or another booster).
    @discardableResult
    mutating func undo() -> Bool {
        guard canUndo, let previous = history.popLast() else { return false }
        let undosLeft = state.boosters.undo - 1
        state = previous
        state.boosters.undo = undosLeft
        return true
    }

    // MARK: Resolution

    private mutating func resolve(from origin: HexCoord) -> [GameEvent] {
        var events: [GameEvent] = []
        var queue: [(cell: HexCoord, chain: Int)] = [(origin, 0)]
        var guardCounter = 0

        while !queue.isEmpty {
            guardCounter += 1
            precondition(guardCounter < 10_000, "Matching did not terminate")
            let (cell, chain) = queue.removeFirst()
            guard let stack = state.board.stack(at: cell), let color = stack.topColor else { continue }
            state.bestChain = max(state.bestChain, chain)

            // Pull matching runs out of the neighbours.
            neighbors: for neighbor in state.board.neighbors(of: cell) {
                guard var neighborStack = state.board.stack(at: neighbor), neighborStack.topColor == color else { continue }
                var current = state.board.stack(at: cell)!
                let run = neighborStack.topRunLength
                guard current.height + run <= level.maxStackHeight else {
                    // The height cap blocks this direction. Try the other one so two touching
                    // stacks with the same top colour are not left behind; the cell's own run
                    // moves across and both stacks are checked again.
                    var receiver = neighborStack
                    let ownRun = current.topRunLength
                    guard receiver.height + ownRun <= level.maxStackHeight else { continue }
                    _ = current.popTopRun()
                    receiver.push(color, count: ownRun)
                    state.board.setStack(current, at: cell)
                    state.board.setStack(receiver, at: neighbor)
                    let points = ownRun * Self.transferPoints
                    state.score += points
                    events.append(.tilesTransferred(from: cell, to: neighbor, color: color, count: ownRun, chain: chain))
                    events.append(.scoreAwarded(points: points, cell: neighbor, chain: chain))
                    queue.append((neighbor, chain))
                    if !current.isEmpty { queue.append((cell, chain + 1)) }
                    break neighbors
                }

                _ = neighborStack.popTopRun()
                current.push(color, count: run)
                state.board.setStack(current, at: cell)
                state.board.setStack(neighborStack, at: neighbor)

                let points = run * Self.transferPoints
                state.score += points
                events.append(.tilesTransferred(from: neighbor, to: cell, color: color, count: run, chain: chain))
                events.append(.scoreAwarded(points: points, cell: cell, chain: chain))
                if !neighborStack.isEmpty { queue.append((neighbor, chain + 1)) }
            }

            // Turn a full run into a pencil.
            if var current = state.board.stack(at: cell), current.topRunLength >= level.pencilSize {
                let removed = current.popTopRun()!
                state.board.setStack(current, at: cell)
                state.pencilsByColor[removed.color, default: 0] += 1
                let regionID = fillNextRegion(of: removed.color)
                let points = removed.count * Self.pencilPoints * (chain + 1)
                state.score += points
                events.append(.pencilCompleted(cell: cell, color: removed.color, tileCount: removed.count, regionID: regionID, chain: chain))
                events.append(.scoreAwarded(points: points, cell: cell, chain: chain))
                if !current.isEmpty { queue.append((cell, chain + 1)) }
            }
        }
        return events
    }

    /// Colours the first unfilled region of `color`, if any is left.
    private mutating func fillNextRegion(of color: TileColor) -> Int? {
        let region = level.artwork.regions.first { $0.color == color && !state.filledRegions.contains($0.id) }
        guard let region else { return nil }
        state.filledRegions.append(region.id)
        return region.id
    }

    // MARK: Status

    private mutating func dealTray() {
        for slot in state.tray.indices where state.tray[slot] == nil && !state.queue.isEmpty {
            state.tray[slot] = state.queue.removeFirst()
        }
    }

    private mutating func evaluateStatus() -> [GameEvent] {
        guard state.status.isPlaying else { return [] }

        if state.filledRegions.count >= level.artwork.regions.count {
            if let remaining = movesRemaining { state.score += remaining * Self.leftoverMovePoints }
            let stars = starReport.stars
            state.status = .won(stars: stars)
            return [.levelCompleted(stars: stars)]
        }

        let reason: FailReason?
        if let remaining = movesRemaining, remaining == 0 {
            reason = .outOfMoves
        } else if state.trayIsEmpty && state.queue.isEmpty {
            reason = .outOfSupply
        } else if !state.trayIsEmpty && state.board.emptyCells.isEmpty && state.boosters.hammer == 0 {
            reason = .boardFull
        } else {
            reason = nil
        }
        guard let reason else { return [] }
        state.status = .failed(reason)
        return [.levelFailed(reason: reason)]
    }

    /// How many booster charges this run has spent (a charge spent on Undo stays spent).
    var boostersUsed: Int { max(0, level.boosters.total - state.boosters.total) }

    /// The stars a win would earn right now: one for finishing, one for the level's goal, and one
    /// for finishing without spending a booster.
    var starReport: StarReport {
        StarReport(goalMet: level.starGoal.isMet(by: state), boosterFree: boostersUsed == 0)
    }

    private mutating func pushHistory() {
        history.append(state)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }
}
