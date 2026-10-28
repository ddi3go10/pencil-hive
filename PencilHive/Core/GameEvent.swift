import Foundation

enum FailReason: String, Codable, Hashable {
    /// No placements left but the picture is unfinished.
    case outOfMoves
    /// Tray stacks are waiting but every cell is taken.
    case boardFull
    /// All stacks were placed and the picture is still unfinished.
    case outOfSupply
}

enum GameStatus: Hashable, Codable {
    case playing
    case won(stars: Int)
    case failed(FailReason)

    var isPlaying: Bool { self == .playing }
    var isWon: Bool { if case .won = self { return true } else { return false } }
}

/// Facts about what just happened, in order. The engine has already applied them to its state;
/// the renderer replays them as animation.
enum GameEvent: Hashable {
    case stackPlaced(slot: Int, cell: HexCoord, stack: TileStack)
    /// The top run of `color` moved from one board stack onto another.
    case tilesTransferred(from: HexCoord, to: HexCoord, color: TileColor, count: Int, chain: Int)
    /// A stack's top run reached the pencil size and was cleared into a pencil.
    case pencilCompleted(cell: HexCoord, color: TileColor, tileCount: Int, regionID: Int?, chain: Int)
    case scoreAwarded(points: Int, cell: HexCoord, chain: Int)
    case trayRefilled(slots: [TileStack?])
    case stackRemoved(cell: HexCoord, stack: TileStack)
    case trayRefreshed(slots: [TileStack?])
    case levelCompleted(stars: Int)
    case levelFailed(reason: FailReason)
}
