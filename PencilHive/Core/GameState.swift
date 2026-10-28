import Foundation

/// Everything that changes while a level is played. A value type, so snapshots (undo, save files,
/// solver nodes) are just copies.
struct GameState: Hashable, Codable {
    var board: HexBoard
    /// The stacks on offer; `nil` marks a slot whose stack was already placed.
    var tray: [TileStack?]
    /// Stacks still waiting to be dealt.
    var queue: [TileStack]
    var movesUsed: Int = 0
    var score: Int = 0
    var pencilsByColor: [TileColor: Int] = [:]
    /// Ids of illustration regions already coloured in, in the order they were filled.
    var filledRegions: [Int] = []
    var boosters: BoosterInventory
    var status: GameStatus = .playing
    var bestChain: Int = 0

    var pencilsCompleted: Int { pencilsByColor.values.reduce(0, +) }
    var trayIsEmpty: Bool { tray.allSatisfy { $0 == nil } }
    var trayStacks: [TileStack] { tray.compactMap { $0 } }
}
