import SwiftUI

/// What the SwiftUI HUD shows. Rebuilt from the engine after every change.
struct HUDSnapshot: Equatable {
    struct GoalChip: Equatable, Identifiable {
        let color: TileColor
        let remaining: Int
        let total: Int
        var id: TileColor { color }
    }

    var score = 0
    var movesUsed = 0
    var movesRemaining: Int?
    var pencilsDone = 0
    var pencilsTotal = 0
    var pencilColors: [TileColor] = []
    var goals: [GoalChip] = []
    var undo = 0, hammer = 0, refresh = 0
    var canUndo = false, canHammer = false, canRefresh = false
    var status: GameStatus = .playing
}

/// One of the three ways to earn a star, shown on the pause and result cards.
struct StarLine: Equatable, Identifiable {
    let text: String
    let earned: Bool
    var id: String { text }
}

enum GameOverlay: Equatable {
    case pause
    case won(stars: Int, score: Int, best: Int, isNewBest: Bool, hasNext: Bool, bestChain: Int, lines: [StarLine])
    case failed(FailReason, canUndo: Bool)
}

/// Bridges the SpriteKit scene to SwiftUI: publishes HUD state, owns the overlays, and handles
/// saving, restarting and level progression.
final class GameViewModel: ObservableObject, GameSceneDelegate {
    @Published private(set) var hud = HUDSnapshot()
    @Published var overlay: GameOverlay? {
        didSet { updateInputBlocking() }
    }
    @Published private(set) var hammerActive = false

    @Published var restartConfirmation = false {
        didSet { updateInputBlocking() }
    }
    @Published private(set) var isResolving = false
    @Published private(set) var hasPlacedStack = false

    var showsPlacementHint: Bool { level.id == 1 && !hasEverWon && !hasPlacedStack }
    var canRequestRestart: Bool {
        !isResolving && scene.phase == .idle && scene.engine.state.status.isPlaying
    }

    private func updateInputBlocking() {
        scene.inputBlocked = overlay != nil || restartConfirmation
    }

    /// True once the player has finished any level, so first-run hints stop appearing.
    var hasEverWon: Bool { !app.progress.bestStars.isEmpty }

    let level: LevelDefinition
    let scene: GameScene
    /// Whether tile symbols are on, so the HUD chips can match the tiles.
    @Published private(set) var showsSymbols: Bool
    private unowned let app: AppModel

    init(level: LevelDefinition, app: AppModel, reducedMotion: @escaping () -> Bool = GameScene.systemReduceMotion) {
        self.level = level
        self.app = app
        showsSymbols = app.showsTileSymbols
        let engine = app.save.restoreEngine(for: level) ?? GameEngine(level: level)
        scene = GameScene(engine: engine, feedback: app.feedback, reducedMotion: reducedMotion)
        scene.gameDelegate = self
        scene.showsSymbols = showsSymbols
        hud = Self.snapshot(of: engine)
        hasPlacedStack = engine.state.movesUsed > 0
        if case .failed(let reason) = engine.state.status {
            overlay = .failed(reason, canUndo: engine.canUndo)
            scene.inputBlocked = true   // property observers do not run inside init
        }
    }

    // MARK: Layout

    func updateAccessibilitySettings(differentiateWithoutColor: Bool) {
        showsSymbols = app.settings.tileSymbols || differentiateWithoutColor
        // A running move finishes before its tiles are redrawn; its event callbacks stay intact.
        scene.showsSymbols = showsSymbols
    }

    func updateInsets(top: CGFloat, bottom: CGFloat) {
        scene.insets = SceneInsets(top: top, bottom: bottom)
    }

    // MARK: Actions

    func undo() { scene.performUndo(); overlay = nil }
    func refreshTray() { scene.performRefresh() }
    func toggleHammer() { scene.toggleHammer() }
    func pause() {
        // Pausing mid-drag drops the stack back in the tray instead of committing a hidden move.
        if scene.phase == .dragging {
            scene.pointerCancelled()
            overlay = .pause
        } else if scene.phase != .animating {
            overlay = .pause
        }
    }
    func resume() { overlay = nil }

    func requestRestart() {
        guard canRequestRestart else { return }
        if scene.engine.state.movesUsed > 0 || scene.engine.boostersUsed > 0 {
            restartConfirmation = true
        } else {
            restart()
        }
    }

    func restart() {
        // Result-card Replay is allowed after celebration; an in-flight move must finish first.
        guard !isResolving, scene.phase != .animating, !scene.finishPending, scene.pendingFlights == 0 else { return }
        restartConfirmation = false
        overlay = nil
        previousBestBeforeWin = nil
        app.save.clearInProgress(levelID: level.id)
        scene.load(engine: GameEngine(level: level))
        app.refresh()
    }

    func exitToMenu() {
        persist()
        app.show(.menu)
    }

    func showLevels() {
        persist()
        app.show(.levels)
    }

    func showGallery() {
        persist()
        app.show(.gallery)
    }

    func playNext() {
        guard let next = app.library.level(after: level.id) else { app.show(.levels); return }
        app.openLevel(next.id)
    }

    // MARK: GameSceneDelegate

    func gameScene(_ scene: GameScene, didUpdate engine: GameEngine) {
        isResolving = false
        hasPlacedStack = hasPlacedStack || engine.state.movesUsed > 0
        hud = Self.snapshot(of: engine)
        persist()
    }

    func gameScene(_ scene: GameScene, didFinishWith status: GameStatus, engine: GameEngine) {
        hud = Self.snapshot(of: engine)
        switch status {
        case .won(let stars):
            let previousBest = recordWinOnce(engine: engine, stars: stars)
            let next = app.library.level(after: level.id)
            let best = max(previousBest, engine.state.score)
            overlay = .won(stars: stars, score: engine.state.score, best: best, isNewBest: engine.state.score > previousBest, hasNext: next != nil, bestChain: engine.state.bestChain, lines: Self.starLines(for: engine))
        case .failed(let reason):
            overlay = .failed(reason, canUndo: engine.canUndo)
        case .playing:
            break
        }
    }

    func gameScene(_ scene: GameScene, hammerModeChanged active: Bool) {
        hammerActive = active
    }

    func gameScene(_ scene: GameScene, engineDidAdvance engine: GameEngine) {
        isResolving = true
        hasPlacedStack = hasPlacedStack || engine.state.movesUsed > 0

        // Booster counts, move counter and button states change the moment a move is accepted. The
        // score, pencil counter and goal chips keep their old values until the animation catches up.
        var fresh = Self.snapshot(of: engine)
        fresh.score = hud.score
        fresh.pencilsDone = hud.pencilsDone
        fresh.goals = hud.goals
        fresh.pencilColors = hud.pencilColors
        fresh.canUndo = false
        fresh.canHammer = false
        fresh.canRefresh = false
        hud = fresh

        // Save as soon as a move is accepted so a kill mid-animation loses nothing. A win is
        // recorded right now too, not when the result card appears about a second later.
        if case .won(let stars) = engine.state.status {
            recordWinOnce(engine: engine, stars: stars)
            app.refresh()
            return
        }
        guard engine.state.status.isPlaying else { return }
        app.save.saveInProgress(engine)
    }

    func gameScene(_ scene: GameScene, pencilLanded color: TileColor, regionID: Int?) {
        guard regionID != nil else { return }
        hud.pencilsDone += 1
        hud.pencilColors.append(color)
        if let index = hud.goals.firstIndex(where: { $0.color == color }) {
            let old = hud.goals[index]
            hud.goals[index] = HUDSnapshot.GoalChip(color: old.color, remaining: max(0, old.remaining - 1), total: old.total)
        }
    }

    // MARK: Helpers

    /// Best score before this run, captured the first time the win is recorded.
    private var previousBestBeforeWin: Int?

    /// Records the win in the save file the first time it is called and returns the previous best.
    @discardableResult
    private func recordWinOnce(engine: GameEngine, stars: Int) -> Int {
        if let previous = previousBestBeforeWin { return previous }
        let previous = app.progress.bestScores[level.id] ?? 0
        previousBestBeforeWin = previous
        let next = app.library.level(after: level.id)
        app.save.recordWin(levelID: level.id, nextLevelID: next?.id, stars: stars, score: engine.state.score)
        return previous
    }

    private func persist() {
        app.save.saveInProgress(scene.engine)
        app.refresh()
    }

    /// The three star conditions for `engine`'s level; `earned` reflects the engine's current state.
    static func starLines(for engine: GameEngine) -> [StarLine] {
        let report = engine.starReport
        let finished = engine.state.status.isWon
        return [
            StarLine(text: "Finish the picture", earned: finished),
            StarLine(text: engine.level.starGoal.summary, earned: finished && report.goalMet),
            StarLine(text: "Use no boosters", earned: finished && report.boosterFree),
        ]
    }

    static func snapshot(of engine: GameEngine) -> HUDSnapshot {
        let total = engine.level.goals
        let remaining = engine.remainingGoals
        let chips = total.keys.sorted().map {
            HUDSnapshot.GoalChip(color: $0, remaining: remaining[$0, default: 0], total: total[$0, default: 0])
        }
        return HUDSnapshot(
            score: engine.state.score,
            movesUsed: engine.state.movesUsed,
            movesRemaining: engine.movesRemaining,
            pencilsDone: engine.state.filledRegions.count,
            pencilsTotal: engine.level.totalPencilsNeeded,
            pencilColors: engine.state.filledRegions.compactMap { engine.level.artwork.region(id: $0)?.color },
            goals: chips,
            undo: engine.state.boosters.undo,
            hammer: engine.state.boosters.hammer,
            refresh: engine.state.boosters.refresh,
            canUndo: engine.canUndo,
            canHammer: engine.canHammer,
            canRefresh: engine.canRefresh,
            status: engine.state.status)
    }
}
