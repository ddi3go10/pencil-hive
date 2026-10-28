import Foundation

/// The playing field: a fixed set of valid cells, some of which hold a stack.
struct HexBoard: Hashable, Codable {
    let cells: [HexCoord]
    private let cellSet: Set<HexCoord>
    private(set) var stacks: [HexCoord: TileStack]

    init(cells: [HexCoord], stacks: [HexCoord: TileStack] = [:]) {
        self.cells = cells.sorted()
        self.cellSet = Set(cells)
        self.stacks = stacks.filter { !$0.value.isEmpty }
    }

    func contains(_ cell: HexCoord) -> Bool { cellSet.contains(cell) }
    func stack(at cell: HexCoord) -> TileStack? { stacks[cell] }
    func isEmpty(_ cell: HexCoord) -> Bool { cellSet.contains(cell) && stacks[cell] == nil }

    var emptyCells: [HexCoord] { cells.filter { stacks[$0] == nil } }
    var occupiedCells: [HexCoord] { cells.filter { stacks[$0] != nil } }
    var tileCount: Int { stacks.values.reduce(0) { $0 + $1.height } }

    func neighbors(of cell: HexCoord) -> [HexCoord] {
        cell.neighbors.filter { cellSet.contains($0) }
    }

    mutating func setStack(_ stack: TileStack, at cell: HexCoord) {
        precondition(cellSet.contains(cell), "Cell \(cell) is not on the board")
        if stack.isEmpty {
            stacks[cell] = nil
        } else {
            stacks[cell] = stack
        }
    }

    mutating func removeStack(at cell: HexCoord) -> TileStack? {
        stacks.removeValue(forKey: cell)
    }

    /// Number of tiles of each colour currently on the board.
    var colorCounts: [TileColor: Int] {
        stacks.values.reduce(into: [:]) { total, stack in
            for (color, count) in stack.colorCounts { total[color, default: 0] += count }
        }
    }

    /// True when no two adjacent stacks share a top colour, i.e. nothing is left to match.
    var isStable: Bool {
        for (cell, stack) in stacks {
            guard let top = stack.topColor else { continue }
            for neighbor in neighbors(of: cell) where stacks[neighbor]?.topColor == top {
                return false
            }
        }
        return true
    }

    /// Stable text form used for solver de-duplication and debugging.
    var signature: String {
        occupiedCells.map { cell in
            let letters = stacks[cell]!.tiles.map { String($0.rawValue.prefix(2)) }.joined()
            return "\(cell.q),\(cell.r):\(letters)"
        }.joined(separator: ";")
    }

    // MARK: Codable (dictionary with struct keys is stored as a sorted array)

    private struct Entry: Codable {
        let cell: HexCoord
        let stack: TileStack
    }

    private enum CodingKeys: String, CodingKey { case cells, stacks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cells = try container.decode([HexCoord].self, forKey: .cells)
        let entries = try container.decode([Entry].self, forKey: .stacks)
        self.init(cells: cells, stacks: Dictionary(entries.map { ($0.cell, $0.stack) }, uniquingKeysWith: { $1 }))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cells, forKey: .cells)
        try container.encode(occupiedCells.map { Entry(cell: $0, stack: stacks[$0]!) }, forKey: .stacks)
    }
}
