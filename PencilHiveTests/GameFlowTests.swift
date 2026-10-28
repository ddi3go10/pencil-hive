import Foundation
import Testing

#if !canImport(PencilHiveCore)
import SpriteKit
@testable import PencilHive

/// Covers the SwiftUI/SpriteKit glue, which only exists in the Xcode build.
@Suite("Game flow")
@MainActor
struct GameFlowTests {
    @Test func reducedMotionCompletesPencilsAndRecordsTheWinWithoutFlights() throws {
        let (model, _) = try app()
        let cell = TestLevels.cell(0, 0)
        let level = TestLevels.make(pencilSize: 3,
            prefilled: [(TestLevels.cell(1, 0), [.coral, .coral])],
            supply: [[.coral], [.sky], [.mint]], regions: [.coral])
        let vm = GameViewModel(level: level, app: model, reducedMotion: { true })
        vm.scene.rebuild()
        let node = try #require(vm.scene.trayNodes[0])

        vm.scene.commitPlacement(slot: 0, cell: cell, node: node)

        #expect(vm.scene.engine.state.status.isWon)
        #expect(vm.scene.phase == .finished)
        #expect(vm.scene.finishPending)
        #expect(vm.scene.pendingFlights == 0)
        #expect(vm.hud.pencilsDone == 1)
        #expect(vm.hud.pencilColors == [.coral])
        #expect(model.progress.bestStars[level.id] != nil)
        #expect(vm.scene.fxLayer.children.isEmpty)
        #expect(vm.scene.trayNodes[0] == nil)
        #expect(vm.scene.trayNodes.values.allSatisfy { !$0.hasActions() })
    }

    @Test func reducedMotionCancelsADragWithoutAFlightOrStuckInput() throws {
        let (model, level) = try app()
        let scene = GameScene(engine: GameEngine(level: level), feedback: model.feedback, reducedMotion: { true })
        scene.rebuild()
        let before = scene.engine.state
        scene.pointerDown(at: scene.slotCenters[0])
        #expect(scene.phase == .dragging)
        scene.pointerMoved(to: CGPoint(x: 0, y: 0))
        scene.pointerCancelled()
        #expect(scene.phase == .idle)
        #expect(scene.engine.state == before)
        let node = try #require(scene.trayNodes[0])
        #expect(hypot(node.position.x - scene.slotCenters[0].x, node.position.y - scene.slotCenters[0].y) < 0.01)
        #expect(node.xScale == 1 && node.yScale == 1)
    }

    @Test func reducedMotionBoostersSettleAndKeepUndoWorking() throws {
        let (model, _) = try app()
        let level = TestLevels.make(supply: [[.sky], [.mint], [.lemon], [.rose], [.coral]], regions: [.violet])
        let vm = GameViewModel(level: level, app: model, reducedMotion: { true })
        let cell = TestLevels.cell(0, 0)
        vm.scene.rebuild()
        vm.scene.commitPlacement(slot: 0, cell: cell, node: try #require(vm.scene.trayNodes[0]))
        vm.refreshTray()
        #expect(vm.scene.phase == .idle && !vm.isResolving)
        #expect(vm.scene.engine.state.boosters.refresh == level.boosters.refresh - 1)
        vm.scene.smash(cell)
        #expect(vm.scene.phase == .idle && !vm.isResolving)
        #expect(vm.scene.engine.state.board.stack(at: cell) == nil)
        #expect(vm.scene.engine.state.boosters.hammer == level.boosters.hammer - 1)
        vm.undo()
        #expect(vm.scene.phase == .idle)
        #expect(vm.scene.engine.state.board.stack(at: cell) == TileStack([.sky]))
    }

    @Test func liveTileSymbolsUpdateTheHudAndDeferRedrawUntilPlaybackFinishes() throws {
        let (model, level) = try app()
        let vm = GameViewModel(level: level, app: model)
        vm.updateAccessibilitySettings(differentiateWithoutColor: false)
        vm.scene.rebuild()
        let before = vm.scene.engine.state
        vm.scene.phase = .animating

        vm.updateAccessibilitySettings(differentiateWithoutColor: true)

        #expect(vm.showsSymbols && vm.scene.showsSymbols)
        #expect(vm.scene.needsRebuild)
        #expect(!vm.scene.art.showsSymbols)
        vm.scene.finishPlayback()
        #expect(vm.scene.art.showsSymbols)
        #expect(vm.scene.engine.state == before)
        #expect(vm.scene.phase == .idle)
        vm.updateAccessibilitySettings(differentiateWithoutColor: false)
        #expect(!vm.showsSymbols && !vm.scene.art.showsSymbols)
        model.setTileSymbols(true)
        vm.updateAccessibilitySettings(differentiateWithoutColor: false)
        #expect(vm.showsSymbols && vm.scene.art.showsSymbols)
    }

    private func app() throws -> (AppModel, LevelDefinition) {
        let model = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
        let level = try #require(model.library.first)
        return (model, level)
    }

    private func wonEngine(for level: LevelDefinition, score: Int) -> GameEngine {
        var state = GameEngine(level: level).state
        state.score = score
        state.movesUsed = 3
        state.status = .won(stars: 2)
        return GameEngine(level: level, state: state)
    }

    @Test func aWinIsSavedTheMomentItHappensNotWhenTheCardAppears() throws {
        let (model, level) = try app()
        let viewModel = GameViewModel(level: level, app: model)
        let engine = wonEngine(for: level, score: 700)

        viewModel.gameScene(viewModel.scene, engineDidAdvance: engine)   // move accepted, animations still playing

        #expect(model.save.progress.bestStars[level.id] == 2)
        #expect(model.save.progress.bestScores[level.id] == 700)
        if let next = model.library.level(after: level.id) { #expect(model.save.isUnlocked(next.id)) }
    }

    @Test func theResultCardStillReportsANewBestAfterTheEarlySave() throws {
        let (model, level) = try app()
        let viewModel = GameViewModel(level: level, app: model)
        let engine = wonEngine(for: level, score: 700)

        viewModel.gameScene(viewModel.scene, engineDidAdvance: engine)
        viewModel.gameScene(viewModel.scene, didUpdate: engine)          // clears the in-progress save
        viewModel.gameScene(viewModel.scene, didFinishWith: engine.state.status, engine: engine)

        guard case let .won(stars, score, best, isNewBest, _, _, lines)? = viewModel.overlay else {
            Issue.record("Expected the win card, got \(String(describing: viewModel.overlay))")
            return
        }
        #expect(stars == 2 && score == 700 && best == 700)
        #expect(isNewBest)
        #expect(lines.count == 3 && lines[0].earned)
        #expect(model.save.data.inProgress == nil)
    }

    @Test func boardAndSupplyStayCenteredAcrossPhoneSizes() throws {
        let (model, _) = try app()
        for size in [CGSize(width: 375, height: 580), CGSize(width: 402, height: 750), CGSize(width: 440, height: 850)] {
            for level in model.library.levels {
                let scene = GameScene(engine: GameEngine(level: level), feedback: model.feedback)
                scene.size = size
                scene.insets = SceneInsets(top: 122, bottom: 92)
                scene.rebuild()
                let bounds = HexLayout.unitBounds(of: level.cells)
                let left = scene.layout.origin.x + bounds.minX * scene.layout.size
                let right = scene.layout.origin.x + bounds.maxX * scene.layout.size
                #expect(abs((left + right) / 2 - size.width / 2) < 0.01)
                #expect(left >= 11.9 && right <= size.width - 11.9)
                #expect(abs(scene.slotCenters.map(\.x).reduce(0, +) / CGFloat(level.trayCount) - size.width / 2) < 0.01)
                let bottom = scene.layout.origin.y + bounds.minY * scene.layout.size
                let top = scene.layout.origin.y + bounds.maxY * scene.layout.size
                let stackLift = CGFloat(level.maxStackHeight - 1) * scene.art.thickness
                #expect(bottom > scene.slotCenters[0].y + stackLift + scene.layout.height / 2)
                #expect(top + stackLift < size.height - scene.insets.top)
                #expect(scene.pencilTarget.y > top + stackLift)
            }
        }
    }

    @Test func theBoardUsesTheSpaceFreedByThePicture() throws {
        let (model, level) = try app()
        let scene = GameScene(engine: GameEngine(level: level), feedback: model.feedback)
        scene.size = CGSize(width: 390, height: 700)
        scene.insets = SceneInsets(top: 100, bottom: 84)
        scene.rebuild()
        // The previous picture-panel layout rendered 31.1-point hexes at this screen size.
        #expect(scene.layout.size > 31.1 * 1.1)
    }

    @Test func galleryCollectsSavedWinsAndSurvivesReplayingALevel() throws {
        let storage = InMemorySaveStorage()
        let model = AppModel(save: SaveStore(storage: storage), bundle: .main)
        let level = try #require(model.library.first)
        #expect(model.completedLevels.isEmpty)
        let vm = GameViewModel(level: level, app: model)
        let engine = wonEngine(for: level, score: 700)
        vm.scene.engine = engine
        vm.gameScene(vm.scene, engineDidAdvance: engine)
        vm.gameScene(vm.scene, didFinishWith: engine.state.status, engine: engine)
        #expect(model.completedLevels.map(\.id) == [level.id])
        vm.showGallery()
        #expect(model.screen == .gallery)
        let reloaded = AppModel(save: SaveStore(storage: storage), bundle: .main)
        #expect(reloaded.completedLevels.map(\.id) == [level.id])
        reloaded.openLevel(level.id)
        #expect(reloaded.screen == .game(level.id))
        #expect(reloaded.completedLevels.map(\.id) == [level.id])
    }

    @Test func releaseTargetsTheVisibleStackEvenWithoutAMoveEvent() throws {
        let (model, level) = try app()
        let scene = GameScene(engine: GameEngine(level: level), feedback: model.feedback)
        scene.rebuild()
        let target = try #require(scene.engine.legalCells.first)
        let center = scene.layout.center(of: target)
        scene.pointerDown(at: scene.slotCenters[0])
        #expect(scene.phase == .dragging)
        scene.pointerUp(at: CGPoint(x: center.x, y: center.y - scene.dragLift))
        #expect(scene.engine.state.movesUsed == 1)
    }

    @Test func progressFillsWhenAPencilLands() throws {
        let (model, level) = try app()
        let viewModel = GameViewModel(level: level, app: model)
        let region = try #require(level.artwork.regions.first)
        var state = viewModel.scene.engine.state
        state.filledRegions = [region.id]
        state.pencilsByColor = [region.color: 1]
        let advanced = GameEngine(level: level, state: state)
        viewModel.gameScene(viewModel.scene, engineDidAdvance: advanced)
        #expect(viewModel.hud.pencilsDone == 0)
        viewModel.gameScene(viewModel.scene, pencilLanded: region.color, regionID: region.id)
        #expect(viewModel.hud.pencilsDone == 1)
        #expect(viewModel.hud.pencilColors == [region.color])
        viewModel.gameScene(viewModel.scene, didUpdate: advanced)
        #expect(viewModel.hud.pencilsDone == 1)
        #expect(viewModel.hud.pencilColors == [region.color])
    }

    @Test func restartingCannotCancelAnActiveMoveOrWinCelebration() throws {
        let (model, level) = try app()
        let vm = GameViewModel(level: level, app: model)
        vm.scene.load(engine: wonEngine(for: level, score: 700))
        vm.scene.phase = .animating
        vm.scene.finishPending = true
        let before = vm.scene.engine.state
        vm.restart()
        #expect(vm.scene.engine.state == before)
        #expect(vm.scene.finishPending)
    }

    @Test func mixedStackLabelCountsOnlyTheMovableTopRun() {
        let node = StackNode(stack: TileStack([.lemon, .coral, .coral]), art: TileArt(hexSize: 30))
        let label = node.children.compactMap { $0 as? SKLabelNode }.first
        #expect(label?.text == "2")
        _ = node.detachTop(2)
        #expect(label?.text == "1")
        node.append(.lemon)
        #expect(label?.text == "2")
    }

    @Test func anUnneededPencilDoesNotFlyToThePicture() throws {
        let (model, level) = try app()
        let scene = GameScene(engine: GameEngine(level: level), feedback: model.feedback)
        scene.rebuild()
        let cell = try #require(scene.engine.state.board.occupiedCells.first)
        let stack = try #require(scene.engine.state.board.stack(at: cell))
        scene.play([.pencilCompleted(cell: cell, color: stack.topColor!, tileCount: 1, regionID: nil, chain: 0)], dragged: nil) {}
        #expect(scene.pendingFlights == 0)
    }

    @Test func restartRequestCanBeCancelledWithoutLosingTheBoardOrSave() throws {
        let (model, level) = try app()
        let vm = GameViewModel(level: level, app: model)
        var engine = vm.scene.engine
        _ = engine.place(slot: 0, at: try #require(engine.legalCells.first))
        vm.scene.load(engine: engine)
        let before = vm.scene.engine.state
        let saved = model.save.data
        vm.requestRestart()
        #expect(vm.restartConfirmation)
        #expect(vm.scene.inputBlocked)
        #expect(vm.scene.engine.state == before)
        #expect(model.save.data == saved)
        vm.restartConfirmation = false
        #expect(!vm.scene.inputBlocked)
        #expect(vm.scene.engine.state == before)
        vm.requestRestart()
        vm.restart()
        #expect(vm.scene.engine.state.movesUsed == 0)
        #expect(!vm.restartConfirmation)
    }

    @Test func placementHintStaysDismissedAfterUndo() throws {
        let (model, level) = try app()
        let vm = GameViewModel(level: level, app: model)
        #expect(vm.showsPlacementHint)
        var engine = vm.scene.engine
        _ = engine.place(slot: 0, at: try #require(engine.legalCells.first))
        vm.gameScene(vm.scene, engineDidAdvance: engine)
        #expect(!vm.showsPlacementHint)
        let undone = engine.undo()
        #expect(undone)
        vm.scene.load(engine: engine)
        #expect(vm.hud.movesUsed == 0)
        #expect(!vm.showsPlacementHint)
    }

    @Test func restartRequestIsIgnoredDuringPlaybackAndAfterFinish() throws {
        let (model, level) = try app()
        let vm = GameViewModel(level: level, app: model)
        vm.scene.rebuild()
        vm.scene.phase = .animating
        #expect(!vm.canRequestRestart)
        vm.requestRestart()
        #expect(!vm.restartConfirmation)
        #expect(vm.scene.phase == .animating)
        vm.scene.load(engine: wonEngine(for: level, score: 700))
        #expect(!vm.canRequestRestart)
        let before = vm.scene.engine.state
        vm.requestRestart()
        #expect(vm.scene.engine.state == before)
    }

    @Test func tallStackTargetsItsVisibleTopFace() throws {
        let (model, level) = try app()
        var state = GameEngine(level: level).state
        state.tray[0] = TileStack(Array(repeating: .sky, count: 8))
        let scene = GameScene(engine: GameEngine(level: level, state: state), feedback: model.feedback)
        scene.rebuild()
        let cell = try #require(scene.engine.legalCells.first)
        let target = scene.layout.center(of: cell)
        scene.pointerDown(at: scene.slotCenters[0])
        scene.pointerMoved(to: CGPoint(x: target.x, y: target.y - scene.dragLift))
        let drag = try #require(scene.drag)
        let faceY = drag.node.position.y + drag.node.localPosition(ofTile: 7).y * drag.node.yScale
        #expect(abs(faceY - target.y) < 0.01)
        #expect(drag.target == cell)
    }

    @Test func hammerTargetsTheVisibleFaceInsteadOfANearerNeighborCenter() throws {
        let (model, level) = try app()
        let tall = HexCoord(q: 0, r: 0)
        let neighbor = HexCoord(q: 0, r: -1)
        var state = GameEngine(level: level).state
        state.board = HexBoard(cells: level.cells, stacks: [
            tall: TileStack((0..<10).map { $0.isMultiple(of: 2) ? .sky : .coral }),
            neighbor: TileStack([.coral]),
        ])
        let scene = GameScene(engine: GameEngine(level: level, state: state), feedback: model.feedback)
        scene.rebuild()
        scene.hammerMode = true

        // This is the center of the tall stack's rendered top face. Its vertical offset makes
        // the short neighbor's cell center closer, which used to direct the hammer to that cell.
        let topFace = CGPoint(
            x: scene.layout.center(of: tall).x,
            y: scene.layout.center(of: tall).y + 9 * scene.art.thickness
        )
        scene.pointerDown(at: topFace)

        #expect(scene.engine.state.board.stack(at: tall) == nil)
        #expect(scene.engine.state.board.stack(at: neighbor) == TileStack([.coral]))
    }

    @Test func hammerTargetsTheTopFaceOfAnIsolatedTallStack() throws {
        let (model, level) = try app()
        let tall = HexCoord(q: 0, r: 0)
        var state = GameEngine(level: level).state
        state.board = HexBoard(cells: level.cells, stacks: [
            tall: TileStack((0..<10).map { $0.isMultiple(of: 2) ? .sky : .coral }),
        ])
        let scene = GameScene(engine: GameEngine(level: level, state: state), feedback: model.feedback)
        scene.rebuild()
        scene.hammerMode = true

        // The old nearest-cell hit test rejected this point because it is 1.44 hex sizes above
        // the only cell center, outside its 1.1-size radius.
        let topFace = CGPoint(
            x: scene.layout.center(of: tall).x,
            y: scene.layout.center(of: tall).y + 9 * scene.art.thickness
        )
        scene.pointerDown(at: topFace)

        #expect(scene.engine.state.board.stack(at: tall) == nil)
    }

    @Test func aResizeDuringAMoveWaitsForTheMoveToSettle() throws {
        let (model, level) = try app()
        let scene = GameScene(engine: GameEngine(level: level), feedback: model.feedback)
        scene.rebuild()
        scene.phase = .animating
        let before = scene.children.count

        scene.insets = SceneInsets(top: 60, bottom: 30)

        #expect(scene.needsRebuild)
        #expect(scene.children.count == before)      // nothing was torn down mid-animation
        scene.finishPlayback()                       // the move ends: now the redraw happens
        #expect(!scene.needsRebuild)
        #expect(scene.phase == .idle)
    }

    @Test func winningOrFailingMoveUpdatesMovesAndDisablesBoostersDuringPlayback() throws {
        let (model, _) = try app()
        let level = TestLevels.make(supply: [[.sky], [.mint]], regions: [.violet], moveLimit: 1)
        let vm = GameViewModel(level: level, app: model)
        var engine = vm.scene.engine
        _ = engine.place(slot: 0, at: TestLevels.cell(0, 0))
        #expect(engine.state.status == .failed(.outOfMoves))

        vm.gameScene(vm.scene, engineDidAdvance: engine)
        #expect(vm.hud.movesUsed == 1)
        #expect(vm.hud.movesRemaining == 0)
        #expect(!vm.hud.canUndo && !vm.hud.canHammer && !vm.hud.canRefresh)

        vm.gameScene(vm.scene, didFinishWith: engine.state.status, engine: engine)
        #expect(vm.hud.canUndo)
    }

    @Test func requestRestartConfirmsWhenABoosterWasSpentAtMoveZero() throws {
        let (model, level) = try app()
        let vm = GameViewModel(level: level, app: model)
        var engine = vm.scene.engine
        _ = engine.useRefresh()
        _ = engine.undo()
        vm.scene.load(engine: engine)
        #expect(vm.scene.engine.state.movesUsed == 0)
        #expect(vm.scene.engine.boostersUsed > 0)
        vm.requestRestart()
        #expect(vm.restartConfirmation)
    }
}
#endif
