import Foundation

/// Static checks that catch broken level data before it ships.
enum LevelValidator {
    static func validate(_ level: LevelDefinition) -> [String] {
        var problems: [String] = []
        func fail(_ message: String) { problems.append("Level \(level.id): \(message)") }

        // Absurd numbers would overflow or take forever in the checks below, so refuse them first.
        func outOfRange(_ name: String, _ value: Int, _ range: ClosedRange<Int>) {
            if !range.contains(value) { fail("\(name) \(value) is outside \(range.lowerBound)...\(range.upperBound)") }
        }
        outOfRange("boardRadius", level.boardRadius, 0...20)
        outOfRange("pencilSize", level.pencilSize, 2...50)
        outOfRange("maxStackHeight", level.maxStackHeight, 1...100)
        outOfRange("trayCount", level.trayCount, 1...8)
        outOfRange("supply size", level.supply.count, 0...2_000)
        outOfRange("prefilled count", level.prefilled.count, 0...2_000)
        outOfRange("removed count", level.removed.count, 0...2_000)
        outOfRange("artwork region count", level.artwork.regions.count, 0...500)
        outOfRange("undo boosters", level.boosters.undo, 0...99)
        outOfRange("hammer boosters", level.boosters.hammer, 0...99)
        outOfRange("refresh boosters", level.boosters.refresh, 0...99)
        if let limit = level.moveLimit { outOfRange("moveLimit", limit, 1...1_000) }
        let cellLimit = -100...100
        for cell in level.removed + level.prefilled.map(\.cell) where !cellLimit.contains(cell.q) || !cellLimit.contains(cell.r) {
            fail("cell \(cell) is far outside the board")
        }
        for stack in level.supply + level.prefilled.map(\.stack) where stack.height > 1_000 { fail("a stack has \(stack.height) tiles") }
        if !problems.isEmpty { return problems }

        if level.pencilSize < 2 { fail("pencilSize must be at least 2") }
        if level.maxStackHeight < level.pencilSize { fail("maxStackHeight is smaller than pencilSize") }
        if level.trayCount < 1 { fail("trayCount must be at least 1") }
        if level.artwork.regions.isEmpty { fail("artwork has no regions") }
        if Set(level.artwork.regions.map(\.id)).count != level.artwork.regions.count { fail("duplicate region ids") }

        let board = level.makeInitialBoard()
        if Set(board.cells).count != board.cells.count { fail("duplicate cells") }
        if level.prefilled.count != Set(level.prefilled.map(\.cell)).count { fail("duplicate prefilled cells") }
        for item in level.prefilled {
            if !board.contains(item.cell) { fail("prefilled cell \(item.cell) is not on the board") }
            if item.stack.isEmpty { fail("prefilled stack at \(item.cell) is empty") }
            if item.stack.height > level.maxStackHeight { fail("prefilled stack at \(item.cell) is too tall") }
            if item.stack.topRunLength >= level.pencilSize { fail("prefilled stack at \(item.cell) is already a pencil") }
        }
        if !board.isStable { fail("initial board has touching stacks with the same top colour") }
        if board.emptyCells.count < level.trayCount { fail("not enough empty cells for the first tray") }

        if level.supply.isEmpty { fail("supply is empty") }
        for (index, stack) in level.supply.enumerated() {
            if stack.isEmpty { fail("supply stack \(index) is empty") }
            if stack.height > level.maxStackHeight { fail("supply stack \(index) is too tall") }
            if stack.topRunLength >= level.pencilSize { fail("supply stack \(index) is already a pencil") }
        }

        let budget = level.tileBudget
        for (color, regions) in level.goals {
            let needed = regions * level.pencilSize
            let have = budget[color, default: 0]
            if have < needed { fail("needs \(needed) \(color.rawValue) tiles but only \(have) exist") }
        }
        switch level.starGoal {
        case .chain(let depth): if depth < 2 { fail("a chain goal needs a depth of at least 2") }
        case .stacks(let limit):
            if limit < 1 { fail("a stacks goal must be positive") }
            if limit < Int.max, limit >= level.supply.count { fail("the stacks goal is not below the number of stacks, so it would be free") }
        case .score(let target): if target < 1 { fail("a score goal must be positive") }
        }
        if let limit = level.moveLimit, limit < 1 { fail("moveLimit must be positive") }
        return problems
    }
}
