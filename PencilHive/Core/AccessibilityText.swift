import Foundation

/// Plain-language descriptions for VoiceOver. Kept free of UI so they can be tested.
enum AccessibilityText {
    static func tiles(_ count: Int) -> String { count == 1 ? "1 tile" : "\(count) tiles" }

    /// "4 tiles, coral on top, then amber" (the colour under the top run, when there is one).
    static func stack(_ stack: TileStack) -> String {
        guard let top = stack.topColor else { return "empty" }
        let run = stack.topRunLength
        var text = "\(tiles(stack.height)), \(top.displayName.lowercased()) on top"
        if run > 1 { text += " (\(run) in a row)" }
        if stack.height > run {
            let below = stack.tiles[stack.height - run - 1]
            text += ", then \(below.displayName.lowercased())"
        }
        return text
    }

    /// Row and position of each cell, counted from the top of the board and from the left.
    /// Axial rows run down the screen as `r` grows; within a row the cells run left to right.
    static func positions(of cells: [HexCoord]) -> [HexCoord: (row: Int, column: Int)] {
        let rows = Dictionary(grouping: cells, by: \.r)
        var result: [HexCoord: (row: Int, column: Int)] = [:]
        for (rowIndex, r) in rows.keys.sorted().enumerated() {
            for (columnIndex, cell) in rows[r, default: []].sorted(by: { $0.q < $1.q }).enumerated() {
                result[cell] = (rowIndex + 1, columnIndex + 1)
            }
        }
        return result
    }

    static func cell(row: Int, column: Int, stack: TileStack?) -> String {
        let place = "Row \(row), cell \(column)"
        guard let stack, !stack.isEmpty else { return "\(place), empty" }
        return "\(place), \(Self.stack(stack))"
    }

    /// What a move did, in the order it happened, for one spoken announcement.
    static func summary(of events: [GameEvent], score: Int) -> String {
        var parts: [String] = []
        var bestChain = 0
        for event in events {
            switch event {
            case let .tilesTransferred(_, _, color, count, chain):
                parts.append("\(tiles(count)) of \(color.displayName.lowercased()) moved")
                bestChain = max(bestChain, chain)
            case let .pencilCompleted(_, color, _, regionID, chain):
                parts.append(regionID == nil
                    ? "\(color.displayName) pencil not needed for the picture; score earned"
                    : "\(color.displayName) pencil done")
                bestChain = max(bestChain, chain)
            case .trayRefilled, .trayRefreshed: parts.append("new stacks dealt")
            case .stackRemoved: parts.append("stack smashed")
            default: break
            }
        }
        if bestChain >= 1 { parts.append("chain of \(bestChain + 1)") }
        parts.append("score \(score)")
        return parts.joined(separator: ". ")
    }

    static func win(stars: Int, score: Int) -> String {
        "Picture complete. \(stars) of 3 stars. Score \(score)."
    }

    static func fail(_ reason: FailReason) -> String { "\(headline(reason)). \(detail(reason))" }

    static func headline(_ reason: FailReason) -> String {
        switch reason {
        case .outOfMoves: return "Out of moves"
        case .boardFull: return "Board is full"
        case .outOfSupply: return "Out of stacks"
        }
    }

    static func detail(_ reason: FailReason) -> String {
        switch reason {
        case .outOfMoves: return "You ran out of placements before the picture was finished."
        case .boardFull: return "There is no empty cell left for the next stack."
        case .outOfSupply: return "Every stack has been placed but the picture isn't finished."
        }
    }
}
