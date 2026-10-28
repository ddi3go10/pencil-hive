import Foundation

#if canImport(PencilHiveCore)
@testable import PencilHiveCore
#else
@testable import PencilHive
#endif

/// Small hand-made levels for rule tests, so each test states only what it cares about.
enum TestLevels {
    static func make(
        pencilSize: Int = 3,
        radius: Int = 2,
        removed: [HexCoord] = [],
        prefilled: [(HexCoord, [TileColor])] = [],
        supply: [[TileColor]] = [[.coral]],
        regions: [TileColor] = [.coral],
        moveLimit: Int? = nil,
        trayCount: Int = 3,
        maxStackHeight: Int = 12,
        boosters: BoosterInventory = BoosterInventory(undo: 3, hammer: 1, refresh: 1),
        starGoal: StarGoal = .none
    ) -> LevelDefinition {
        let artwork = Artwork(
            name: "Test",
            paper: "#FFFFFF",
            regions: regions.enumerated().map { ArtRegion(id: $0.offset + 1, color: $0.element, shape: .rect(x: 0, y: 0, w: 10, h: 10, radius: 0)) })
        return LevelDefinition(
            id: 99, name: "Test", pencilSize: pencilSize, maxStackHeight: maxStackHeight, moveLimit: moveLimit,
            trayCount: trayCount, boardRadius: radius, removed: removed,
            prefilled: prefilled.map { LevelDefinition.Prefilled(cell: $0.0, stack: TileStack($0.1)) },
            supply: supply.map { TileStack($0) }, boosters: boosters, starGoal: starGoal, artwork: artwork)
    }

    static func cell(_ q: Int, _ r: Int) -> HexCoord { HexCoord(q: q, r: r) }

    /// Directory holding the shipped level JSON files.
    static var levelsDirectory: URL {
        #if canImport(PencilHiveCore)
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PencilHive/Resources/Levels")
        #else
        // The iOS test host must read its packaged resources, not the Mac checkout. Reading the
        // host's Documents directory can wait on a macOS privacy prompt, and is not portable.
        Bundle.main.bundleURL.appendingPathComponent("Levels")
        #endif
    }
}

extension GameEngine {
    /// Places the first tray stack that equals `colors` on `cell`.
    @discardableResult
    mutating func placeStack(_ colors: [TileColor], at cell: HexCoord) -> [GameEvent] {
        guard let slot = state.tray.firstIndex(where: { $0 == TileStack(colors) }) else { return [] }
        return place(slot: slot, at: cell)
    }
}

extension Array where Element == GameEvent {
    var transfers: [GameEvent] { filter { if case .tilesTransferred = $0 { return true } else { return false } } }
    var pencils: [GameEvent] { filter { if case .pencilCompleted = $0 { return true } else { return false } } }
}
