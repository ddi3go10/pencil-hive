import Foundation

/// A pile of hex tiles, stored bottom to top.
struct TileStack: Hashable, Codable {
    private(set) var tiles: [TileColor]

    init(_ tiles: [TileColor] = []) {
        self.tiles = tiles
    }

    var height: Int { tiles.count }
    var isEmpty: Bool { tiles.isEmpty }
    var topColor: TileColor? { tiles.last }

    /// How many tiles of the top colour sit together at the top of the stack.
    var topRunLength: Int {
        guard let top = tiles.last else { return 0 }
        var count = 0
        for tile in tiles.reversed() {
            guard tile == top else { break }
            count += 1
        }
        return count
    }

    /// Removes and returns the whole top run of one colour.
    mutating func popTopRun() -> (color: TileColor, count: Int)? {
        guard let color = tiles.last else { return nil }
        let count = topRunLength
        tiles.removeLast(count)
        return (color, count)
    }

    mutating func push(_ color: TileColor, count: Int) {
        tiles.append(contentsOf: Array(repeating: color, count: count))
    }

    /// Number of tiles of each colour.
    var colorCounts: [TileColor: Int] {
        tiles.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    // Stacks are written as a plain array of colour names in JSON.
    init(from decoder: Decoder) throws {
        tiles = try decoder.singleValueContainer().decode([TileColor].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tiles)
    }
}
