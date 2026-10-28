import Foundation

/// Counts of each booster available in a level.
struct BoosterInventory: Hashable, Codable {
    var undo: Int = 0
    var hammer: Int = 0
    var refresh: Int = 0

    init(undo: Int = 0, hammer: Int = 0, refresh: Int = 0) {
        self.undo = undo
        self.hammer = hammer
        self.refresh = refresh
    }

    var total: Int { undo + hammer + refresh }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        undo = try c.decodeIfPresent(Int.self, forKey: .undo) ?? 0
        hammer = try c.decodeIfPresent(Int.self, forKey: .hammer) ?? 0
        refresh = try c.decodeIfPresent(Int.self, forKey: .refresh) ?? 0
    }
}

/// The extra challenge that earns a level's second star. (The third star is for winning without
/// using a booster, see `GameEngine.starReport`.)
enum StarGoal: Hashable {
    /// Make a chain this deep in a single move; depth counts the first match as x1.
    case chain(Int)
    /// Finish the picture having placed at most this many stacks.
    case stacks(Int)
    /// Finish with at least this score.
    case score(Int)

    /// A goal every win meets, for levels that do not set one.
    static let none = StarGoal.stacks(Int.max)

    func isMet(by state: GameState) -> Bool {
        switch self {
        case .chain(let depth): return state.bestChain + 1 >= depth
        case .stacks(let limit): return state.movesUsed <= limit
        case .score(let target): return state.score >= target
        }
    }

    /// What the player reads on the pause and result cards.
    var summary: String {
        switch self {
        case .chain(let depth): return "Make a chain of x\(depth)"
        case .stacks(let limit): return "Finish with \(limit) stacks or fewer"
        case .score(let target): return "Score \(target) or more"
        }
    }
}

extension StarGoal: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try c.decode(Int.self, forKey: .value)
        switch try c.decode(String.self, forKey: .kind) {
        case "chain": self = .chain(value)
        case "stacks": self = .stacks(value)
        case "score": self = .score(value)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown star goal \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .chain(let value): try c.encode("chain", forKey: .kind); try c.encode(value, forKey: .value)
        case .stacks(let value): try c.encode("stacks", forKey: .kind); try c.encode(value, forKey: .value)
        case .score(let value): try c.encode("score", forKey: .kind); try c.encode(value, forKey: .value)
        }
    }
}

/// Data-only description of a level. Levels are JSON files in `Resources/Levels`.
struct LevelDefinition: Hashable, Codable, Identifiable {
    struct Prefilled: Hashable, Codable {
        let cell: HexCoord
        let stack: TileStack
    }

    let id: Int
    let name: String
    /// How many tiles of one colour make a pencil.
    let pencilSize: Int
    /// A stack cannot grow past this many tiles.
    let maxStackHeight: Int
    /// Stacks the player may place; `nil` means unlimited (the supply is the only limit).
    let moveLimit: Int?
    /// How many stacks are offered at once.
    let trayCount: Int
    /// The board is every cell within this radius of the centre, minus `removed`.
    let boardRadius: Int
    let removed: [HexCoord]
    let prefilled: [Prefilled]
    /// Stacks dealt to the tray, in order.
    let supply: [TileStack]
    let boosters: BoosterInventory
    /// The challenge worth the second star.
    let starGoal: StarGoal
    let artwork: Artwork

    private enum CodingKeys: String, CodingKey {
        case id, name, pencilSize, maxStackHeight, moveLimit, trayCount, boardRadius, removed
        case prefilled, supply, boosters, starGoal, artwork
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        pencilSize = try c.decode(Int.self, forKey: .pencilSize)
        maxStackHeight = try c.decodeIfPresent(Int.self, forKey: .maxStackHeight) ?? 12
        moveLimit = try c.decodeIfPresent(Int.self, forKey: .moveLimit)
        trayCount = try c.decodeIfPresent(Int.self, forKey: .trayCount) ?? 3
        boardRadius = try c.decode(Int.self, forKey: .boardRadius)
        removed = try c.decodeIfPresent([HexCoord].self, forKey: .removed) ?? []
        prefilled = try c.decodeIfPresent([Prefilled].self, forKey: .prefilled) ?? []
        supply = try c.decode([TileStack].self, forKey: .supply)
        boosters = try c.decodeIfPresent(BoosterInventory.self, forKey: .boosters) ?? BoosterInventory()
        starGoal = try c.decodeIfPresent(StarGoal.self, forKey: .starGoal) ?? .none
        artwork = try c.decode(Artwork.self, forKey: .artwork)
    }

    init(
        id: Int, name: String, pencilSize: Int, maxStackHeight: Int = 12, moveLimit: Int? = nil,
        trayCount: Int = 3, boardRadius: Int, removed: [HexCoord] = [], prefilled: [Prefilled] = [],
        supply: [TileStack], boosters: BoosterInventory = BoosterInventory(),
        starGoal: StarGoal = .none, artwork: Artwork
    ) {
        self.id = id; self.name = name; self.pencilSize = pencilSize; self.maxStackHeight = maxStackHeight
        self.moveLimit = moveLimit; self.trayCount = trayCount; self.boardRadius = boardRadius
        self.removed = removed; self.prefilled = prefilled; self.supply = supply
        self.boosters = boosters; self.starGoal = starGoal; self.artwork = artwork
    }

    /// The valid cells of this level's board.
    var cells: [HexCoord] {
        let excluded = Set(removed)
        return HexCoord.hexagon(radius: boardRadius).filter { !excluded.contains($0) }
    }

    /// Pencils of each colour needed to finish the illustration.
    var goals: [TileColor: Int] { artwork.goals }
    var totalPencilsNeeded: Int { artwork.regions.count }

    /// The board as it looks before the first move.
    func makeInitialBoard() -> HexBoard {
        HexBoard(cells: cells, stacks: Dictionary(prefilled.map { ($0.cell, $0.stack) }, uniquingKeysWith: { $1 }))
    }

    /// Every tile in the level (board plus supply) per colour.
    var tileBudget: [TileColor: Int] {
        var total = makeInitialBoard().colorCounts
        for stack in supply {
            for (color, count) in stack.colorCounts { total[color, default: 0] += count }
        }
        return total
    }
}
