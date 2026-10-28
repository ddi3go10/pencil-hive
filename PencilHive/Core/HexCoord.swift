import Foundation

/// Axial hex coordinate (`q` = column, `r` = row). The implicit cube coordinate is `s = -q - r`.
/// The renderer uses flat-top hexes, so the six neighbours below go east, north-east, north-west,
/// west, south-west, south-east on screen (`r` grows downward).
struct HexCoord: Hashable, Comparable, Codable, CustomStringConvertible {
    let q: Int
    let r: Int

    init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }

    /// Neighbour offsets in a fixed order. The order matters: matching resolves neighbours in this
    /// order, which keeps the rules deterministic.
    static let directions: [HexCoord] = [
        HexCoord(q: 1, r: 0), HexCoord(q: 1, r: -1), HexCoord(q: 0, r: -1),
        HexCoord(q: -1, r: 0), HexCoord(q: -1, r: 1), HexCoord(q: 0, r: 1),
    ]

    var s: Int { -q - r }

    var neighbors: [HexCoord] {
        Self.directions.map { HexCoord(q: q + $0.q, r: r + $0.r) }
    }

    func distance(to other: HexCoord) -> Int {
        max(abs(q - other.q), abs(r - other.r), abs(s - other.s))
    }

    func isAdjacent(to other: HexCoord) -> Bool { distance(to: other) == 1 }

    /// Every cell within `radius` of the origin, ordered row by row (top to bottom, left to right).
    static func hexagon(radius: Int) -> [HexCoord] {
        guard radius >= 0 else { return [] }
        var cells: [HexCoord] = []
        for r in -radius...radius {
            for q in -radius...radius where abs(-q - r) <= radius {
                cells.append(HexCoord(q: q, r: r))
            }
        }
        return cells
    }

    static func < (lhs: HexCoord, rhs: HexCoord) -> Bool {
        lhs.r != rhs.r ? lhs.r < rhs.r : lhs.q < rhs.q
    }

    var description: String { "(\(q),\(r))" }

    // Compact JSON form: `[q, r]`.
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        q = try container.decode(Int.self)
        r = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(q)
        try container.encode(r)
    }
}
