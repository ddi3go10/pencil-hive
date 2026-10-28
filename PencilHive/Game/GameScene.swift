import SpriteKit

protocol GameSceneDelegate: AnyObject {
    /// The engine state changed (after a move, undo, booster...). Fired once animations settle.
    func gameScene(_ scene: GameScene, didUpdate engine: GameEngine)
    /// The level reached a win or fail state and its animations have finished.
    func gameScene(_ scene: GameScene, didFinishWith status: GameStatus, engine: GameEngine)
    func gameScene(_ scene: GameScene, pencilLanded color: TileColor, regionID: Int?)
    func gameScene(_ scene: GameScene, hammerModeChanged active: Bool)
    /// The engine accepted a move; animations are still playing. Used to save progress early.
    func gameScene(_ scene: GameScene, engineDidAdvance engine: GameEngine)
}

/// Draws the board and tray and turns touches into engine moves.
/// All puzzle rules live in `GameEngine`; this class only renders its state and replays its events.
final class GameScene: SKScene {
    enum Phase { case idle, dragging, animating, finished }

    struct DragState {
        let slot: Int
        let node: StackNode
        var target: HexCoord?
    }

    // MARK: State

    var engine: GameEngine
    weak var gameDelegate: GameSceneDelegate?
    let feedback: Feedback
    /// Print each colour's symbol on its tiles (set before the scene is first drawn).
    var showsSymbols = false
    /// The tray slot a VoiceOver user has picked up, waiting for an empty cell.
    var selectedSlot: Int?
    /// True while a SwiftUI card (pause, win, fail) covers the board, so nothing underneath can act.
    var inputBlocked = false
    /// What the last move did, spoken when its animation settles.
    var pendingAnnouncement: String?
    var insets = SceneInsets() {
        didSet { if insets != oldValue, didBuild { requestRebuild() } }
    }
    /// A resize arrived while a move was animating; `finishPlayback` redraws once it settles.
    var needsRebuild = false

    var phase: Phase = .idle
    var drag: DragState?
    var hammerMode = false {
        didSet {
            guard hammerMode != oldValue else { return }
            updateHammerHighlights()
            gameDelegate?.gameScene(self, hammerModeChanged: hammerMode)
        }
    }

    // MARK: Layout and nodes

    var art = TileArt(hexSize: 28)
    var layout = HexLayout(size: 28)
    var slotCenters: [CGPoint] = []
    /// Pencils land in the HUD meter; the illustration is revealed on the reward screen.
    var pencilTarget = CGPoint.zero
    var cellSprites: [HexCoord: SKSpriteNode] = [:]
    var boardStacks: [HexCoord: StackNode] = [:]
    var trayNodes: [Int: StackNode] = [:]
    let boardLayer = SKNode()
    let stackLayer = SKNode()
    let trayLayer = SKNode()
    let fxLayer = SKNode()
    let dragLayer = SKNode()
    var highlight: SKSpriteNode?
    var didBuild = false
    /// Pencils currently flying to the artwork; a level only ends once they have all landed.
    var pendingFlights = 0
    /// True between a win/fail and the moment the delegate has been told about it.
    var finishPending = false
    /// The finger driving the current drag; other touches are ignored.
    var activeTouch: AnyObject?

    // MARK: Lifecycle

    init(engine: GameEngine, feedback: Feedback) {
        self.engine = engine
        self.feedback = feedback
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = Theme.backgroundTop
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        if !didBuild { rebuild() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 1, size.height > 1, size != oldSize else { return }
        requestRebuild()
    }

    /// Redraws now, or after the current move settles. Rebuilding mid-animation would cancel the
    /// event chain, and with it the win or fail report.
    func requestRebuild() {
        if phase == .animating {
            needsRebuild = true
        } else {
            rebuild()
        }
    }

    // MARK: Layout

    private func computeLayout() {
        let width = size.width, height = size.height
        let cells = engine.level.cells
        let unit = HexLayout.unitBounds(of: cells)

        // Fit the entire board, including the tallest legal pile, between the HUD and tray.
        // Removing the picture panel lets the honeycomb occupy the full playing area.
        let headroom = CGFloat(engine.level.maxStackHeight - 1) * 0.16 + 0.12
        let usableHeight = max(60, height - insets.top - insets.bottom - 28)
        let hexSize = min((width - 24) / unit.width, usableHeight / (unit.height + headroom + 3.6), 58)
        let boardTop = height - insets.top - 12 - headroom * hexSize
        let boardBottom = insets.bottom + hexSize * 3.6 + 16
        let middle = (boardTop + boardBottom) / 2
        layout = HexLayout(
            size: hexSize,
            origin: CGPoint(x: width / 2 - unit.midX * hexSize, y: middle - unit.midY * hexSize))
        // Textures are costly to render, so keep them while the hex size is unchanged (undo, rebuilds).
        if abs(art.hexSize - hexSize) > 0.01 || art.showsSymbols != showsSymbols {
            art = TileArt(hexSize: hexSize, showsSymbols: showsSymbols)
        }

        let count = engine.level.trayCount
        let trayY = insets.bottom + hexSize * 1.05 + 4
        slotCenters = (0..<count).map { CGPoint(x: width * (CGFloat($0) + 0.5) / CGFloat(count), y: trayY) }

        pencilTarget = CGPoint(x: width * 0.45, y: height - 28)
    }

    func rebuild() {
        guard size.width > 1, size.height > 1 else { return }
        needsRebuild = false
        if let slot = selectedSlot, engine.state.tray.indices.contains(slot), engine.state.tray[slot] != nil {} else { selectedSlot = nil }
        removeAllChildren()
        removeAllActions()
        drag = nil
        activeTouch = nil
        pendingFlights = 0
        cellSprites = [:]; boardStacks = [:]; trayNodes = [:]
        highlight = nil
        computeLayout()

        addChild(makeBackground())
        boardLayer.removeAllChildren(); stackLayer.removeAllChildren(); trayLayer.removeAllChildren()
        fxLayer.removeAllChildren(); dragLayer.removeAllChildren()
        boardLayer.zPosition = 10; stackLayer.zPosition = 20; trayLayer.zPosition = 30
        fxLayer.zPosition = 60; dragLayer.zPosition = 50
        [boardLayer, stackLayer, trayLayer, dragLayer, fxLayer].forEach { addChild($0) }

        buildBoard()
        buildTray()
        didBuild = true
        phase = engine.state.status.isPlaying ? .idle : .finished
        updateHammerHighlights()
        refreshAccessibility()
        // A rebuild cancels pending actions; make sure a win/fail that was mid-celebration is still reported.
        if finishPending { reportFinish(after: 0.3) }
    }

    private func makeBackground() -> SKNode {
        let container = SKNode()
        container.zPosition = -10
        let gradient = SKSpriteNode(color: Theme.backgroundTop, size: size)
        gradient.anchorPoint = .zero
        container.addChild(gradient)
        return container
    }

    private func buildBoard() {
        for cell in engine.state.board.cells {
            let sprite = art.cellSprite()
            sprite.position = layout.center(of: cell)
            boardLayer.addChild(sprite)
            cellSprites[cell] = sprite
        }
        for cell in engine.state.board.occupiedCells {
            guard let stack = engine.state.board.stack(at: cell) else { continue }
            let node = StackNode(stack: stack, art: art)
            node.position = layout.center(of: cell)
            node.zPosition = stackZ(for: cell)
            stackLayer.addChild(node)
            boardStacks[cell] = node
        }
    }

    func buildTray() {
        for (slot, stack) in engine.state.tray.enumerated() {
            guard let stack else { continue }
            let node = StackNode(stack: stack, art: art)
            node.position = slotCenters[slot]
            trayLayer.addChild(node)
            trayNodes[slot] = node
        }
    }

    /// Cells lower on screen draw in front, so tall stacks overlap correctly.
    func stackZ(for cell: HexCoord) -> CGFloat {
        1000 - layout.center(of: cell).y
    }

    func updateHammerHighlights() {
        for (cell, node) in boardStacks {
            node.removeAction(forKey: "hammerPulse")
            guard hammerMode, engine.state.board.stack(at: cell) != nil else { node.alpha = 1; continue }
            // Reduce Motion: a steady dim marks the smashable stacks instead of a pulse.
            if reduceMotion { node.alpha = 0.7; continue }
            node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.35), .fadeAlpha(to: 1, duration: 0.35)])), withKey: "hammerPulse")
        }
    }

    // MARK: Engine access

    /// Replaces the engine (for restart) and redraws.
    func load(engine: GameEngine) {
        self.engine = engine
        hammerMode = false
        selectedSlot = nil
        finishPending = false
        rebuild()
        gameDelegate?.gameScene(self, didUpdate: engine)
    }

    func notifyUpdate() {
        gameDelegate?.gameScene(self, didUpdate: engine)
    }
}

extension CGRect {
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
}
