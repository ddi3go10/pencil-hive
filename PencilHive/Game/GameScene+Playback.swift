import SpriteKit

// MARK: Turning engine events into animation

extension GameScene {
    // MARK: Entry points

    func commitPlacement(slot: Int, cell: HexCoord, node: StackNode) {
        phase = .animating
        let events = engine.place(slot: slot, at: cell)
        guard !events.isEmpty else {
            phase = .idle
            return
        }
        trayNodes[slot] = nil
        pendingAnnouncement = AccessibilityText.summary(of: events, score: engine.state.score)
        gameDelegate?.gameScene(self, engineDidAdvance: engine)
        play(events, dragged: node) { [weak self] in self?.finishPlayback() }
    }

    func smash(_ cell: HexCoord) {
        hammerMode = false
        phase = .animating
        let events = engine.useHammer(at: cell)
        guard !events.isEmpty else {
            phase = .idle
            return
        }
        pendingAnnouncement = AccessibilityText.summary(of: events, score: engine.state.score)
        gameDelegate?.gameScene(self, engineDidAdvance: engine)
        play(events, dragged: nil) { [weak self] in self?.finishPlayback() }
    }

    func toggleHammer() {
        guard phase == .idle else { return }
        if engine.canHammer {
            hammerMode.toggle()
            announce(hammerMode ? "Hammer ready. Double tap a stack to smash it." : "Hammer put away.")
            refreshAccessibility()
            feedback.play(.boost)
        } else {
            feedback.play(.error)
        }
    }

    func performRefresh() {
        guard phase == .idle, engine.canRefresh else { feedback.play(.error); return }
        hammerMode = false
        phase = .animating
        let events = engine.useRefresh()
        selectedSlot = nil
        pendingAnnouncement = AccessibilityText.summary(of: events, score: engine.state.score)
        gameDelegate?.gameScene(self, engineDidAdvance: engine)
        play(events, dragged: nil) { [weak self] in self?.finishPlayback() }
    }

    func performUndo() {
        let canAct = phase == .idle || phase == .finished
        guard canAct, engine.canUndo, engine.undo() else { feedback.play(.error); return }
        hammerMode = false
        selectedSlot = nil
        finishPending = false
        feedback.play(.boost)
        feedback.haptic(.medium)
        rebuild()
        [boardLayer, stackLayer, trayLayer].forEach {
            $0.alpha = 0
            $0.run(.fadeIn(withDuration: 0.2))
        }
        notifyUpdate()
    }

    // MARK: Event player

    func play(_ events: [GameEvent], from index: Int = 0, dragged: StackNode?, completion: @escaping () -> Void) {
        guard index < events.count else {
            completion()
            return
        }
        let next: () -> Void = { [weak self] in
            self?.play(events, from: index + 1, dragged: dragged, completion: completion)
        }
        switch events[index] {
        case let .stackPlaced(_, cell, _):
            guard let dragged else { next(); return }
            animatePlacement(node: dragged, cell: cell, then: next)
        case let .tilesTransferred(from, to, color, count, chain):
            animateTransfer(from: from, to: to, color: color, count: count, chain: chain, then: next)
        case let .pencilCompleted(cell, color, tileCount, regionID, chain):
            animatePencil(cell: cell, color: color, tileCount: tileCount, regionID: regionID, chain: chain, then: next)
        case let .scoreAwarded(points, cell, _):
            let base = layout.center(of: cell)
            floatText("+\(points)", at: CGPoint(x: base.x + CGFloat.random(in: -8...8), y: base.y + layout.size * 0.9))
            next()
        case let .trayRefilled(slots):
            animateTrayDeal(slots, clearing: false, then: next)
        case let .trayRefreshed(slots):
            animateTrayDeal(slots, clearing: true, then: next)
        case let .stackRemoved(cell, _):
            animateSmash(cell: cell, then: next)
        case .levelCompleted, .levelFailed:
            next()
        }
    }

    // MARK: Individual animations

    private func animatePlacement(node: StackNode, cell: HexCoord, then next: @escaping () -> Void) {
        let target = layout.center(of: cell)
        node.removeFromParent()
        node.zPosition = stackZ(for: cell)
        stackLayer.addChild(node)
        boardStacks[cell] = node
        let move = SKAction.move(to: target, duration: 0.12)
        move.timingMode = .easeOut
        node.run(.group([move, .scale(to: 1, duration: 0.12)])) { [weak self, weak node] in
            guard let self, let node else { next(); return }
            self.feedback.play(.place)
            self.feedback.haptic(.medium)
            node.run(.sequence([.scaleY(to: 0.9, duration: 0.05), .scaleY(to: 1.05, duration: 0.07), .scaleY(to: 1, duration: 0.05)]))
            let dust = self.layout.center(of: cell)
            self.burst(at: dust, color: SKColor(white: 1, alpha: 0.8), count: 6, radius: self.layout.size * 0.8, size: 2.5)
            self.run(.wait(forDuration: 0.1), completion: next)
        }
    }

    private func animateTransfer(from: HexCoord, to: HexCoord, color: TileColor, count: Int, chain: Int, then next: @escaping () -> Void) {
        guard let source = boardStacks[from], let destination = boardStacks[to] else {
            syncToState()
            next()
            return
        }
        let detached = source.detachTop(count)
        let step = 0.06
        let duration = 0.26
        let baseHeight = destination.height
        for (index, item) in detached.enumerated() {
            let sprite = item.sprite
            let start = CGPoint(x: source.position.x + sprite.position.x, y: source.position.y + sprite.position.y)
            sprite.removeFromParent()
            sprite.position = start
            sprite.zPosition = 10 + CGFloat(index)
            fxLayer.addChild(sprite)

            let local = destination.localPosition(ofTile: baseHeight + index)
            let end = CGPoint(x: destination.position.x + local.x, y: destination.position.y + local.y)
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + layout.size * 1.1))
            let flight = SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration)
            flight.timingMode = .easeInEaseOut
            let tilt = SKAction.sequence([.rotate(toAngle: index.isMultiple(of: 2) ? 0.13 : -0.13, duration: duration * 0.4), .rotate(toAngle: 0, duration: duration * 0.6)])
            let pop = SKAction.sequence([.scale(to: 1.15, duration: duration * 0.4), .scale(to: 1, duration: duration * 0.6)])
            sprite.run(.sequence([
                .wait(forDuration: step * Double(index)),
                .group([flight, pop, tilt]),
                .run { [weak destination] in destination?.adopt(sprite, color: item.color) },
            ]))
        }
        if source.height == 0 {
            source.removeFromParent()
            boardStacks[from] = nil
        }
        feedback.play(.merge)
        feedback.haptic(.light)
        let total = step * Double(max(0, detached.count - 1)) + duration + 0.04
        run(.wait(forDuration: total)) { [weak self, weak destination] in
            destination?.run(.sequence([.scaleY(to: 0.82, duration: 0.06), .scaleY(to: 1.05, duration: 0.08), .scaleY(to: 1, duration: 0.08)]))
            if let self, let destination {
                self.burst(at: CGPoint(x: destination.position.x, y: destination.position.y + CGFloat(destination.height) * self.art.thickness), color: .white, count: 5, radius: self.layout.size * 0.7, size: 2)
            }
            next()
        }
    }

    private func animatePencil(cell: HexCoord, color: TileColor, tileCount: Int, regionID: Int?, chain: Int, then next: @escaping () -> Void) {
        guard let node = boardStacks[cell] else {
            syncToState()
            next()
            return
        }
        let detached = node.detachTop(tileCount)
        let tint = Theme.skColor(color)
        var centre = CGPoint.zero
        for item in detached {
            centre.x += node.position.x + item.sprite.position.x
            centre.y += node.position.y + item.sprite.position.y
        }
        if !detached.isEmpty {
            centre.x /= CGFloat(detached.count)
            centre.y /= CGFloat(detached.count)
        }
        for item in detached {
            let sprite = item.sprite
            let start = CGPoint(x: node.position.x + sprite.position.x, y: node.position.y + sprite.position.y)
            sprite.removeFromParent()
            sprite.position = start
            sprite.zPosition = 10
            fxLayer.addChild(sprite)
            sprite.run(.sequence([
                .group([.move(to: centre, duration: 0.18), .scale(to: 0.55, duration: 0.18)]),
                .removeFromParent(),
            ]))
        }
        if node.height == 0 {
            node.removeFromParent()
            boardStacks[cell] = nil
        }
        if chain > 0 {
            floatText("Chain x\(chain + 1)!", at: CGPoint(x: centre.x, y: centre.y + layout.size * 1.5), color: SKColor(red: 1, green: 0.95, blue: 0.5, alpha: 1), fontSize: 19)
        }

        guard regionID != nil else {
            // This color is already complete: keep the score reward, but never imply picture progress.
            floatText("\(color.displayName) not needed", at: centre, color: Theme.ink, fontSize: 13)
            burst(at: centre, color: SKColor(white: 0.65, alpha: 1), count: 8, radius: layout.size)
            feedback.play(.place)
            run(.wait(forDuration: 0.36), completion: next)
            return
        }

        let pencil = art.pencilSprite(color)
        pencil.position = centre
        pencil.zPosition = 20
        pencil.setScale(0.01)
        pencil.zRotation = .pi / 2
        fxLayer.addChild(pencil)
        pendingFlights += 1

        let target = pencilTarget
        let path = CGMutablePath()
        path.move(to: centre)
        let bow: CGFloat = centre.x < size.width / 2 ? -1 : 1
        path.addQuadCurve(to: target, control: CGPoint(x: (centre.x + target.x) / 2 + bow * size.width * 0.22, y: (centre.y + target.y) / 2))
        let fly = SKAction.follow(path, asOffset: false, orientToPath: true, duration: 0.7)
        fly.timingMode = .easeIn

        ring(at: centre, color: tint, radius: layout.size)
        burst(at: centre, color: tint, count: 16, radius: layout.size * 1.6)
        feedback.play(.pencil)
        feedback.haptic(.success)

        pencil.run(.sequence([
            .wait(forDuration: 0.16),
            .group([.scale(to: 1.25, duration: 0.14), .rotate(toAngle: 0, duration: 0.14, shortestUnitArc: true)]),
            .scale(to: 1, duration: 0.06),
            .group([fly, .scale(to: 0.55, duration: 0.7)]),
            .run { [weak self] in
                guard let self else { return }
                self.feedback.play(.paint)
                self.feedback.haptic(.medium)
                self.gameDelegate?.gameScene(self, pencilLanded: color, regionID: regionID)
                self.burst(at: target, color: tint, count: 18, radius: 36, size: 3.5)
                self.pendingFlights -= 1
            },
            .removeFromParent(),
        ]))
        run(.wait(forDuration: 0.36), completion: next)
    }

    private func animateTrayDeal(_ slots: [TileStack?], clearing: Bool, then next: @escaping () -> Void) {
        var delay = 0.0
        if clearing {
            for (_, node) in trayNodes {
                node.run(.sequence([.group([.moveBy(x: 0, y: -layout.size * 4, duration: 0.18), .fadeOut(withDuration: 0.18)]), .removeFromParent()]))
            }
            trayNodes = [:]
            delay = 0.2
            feedback.play(.boost)
        }
        for (slot, stack) in slots.enumerated() {
            guard let stack, trayNodes[slot] == nil else { continue }
            let node = StackNode(stack: stack, art: art)
            node.position = CGPoint(x: slotCenters[slot].x, y: -layout.size * 3)
            trayLayer.addChild(node)
            trayNodes[slot] = node
            let move = SKAction.move(to: slotCenters[slot], duration: 0.3)
            move.timingMode = .easeOut
            node.run(.sequence([.wait(forDuration: delay + 0.07 * Double(slot)), move]))
        }
        run(.wait(forDuration: delay + 0.35), completion: next)
    }

    private func animateSmash(cell: HexCoord, then next: @escaping () -> Void) {
        guard let node = boardStacks[cell] else { syncToState(); next(); return }
        boardStacks[cell] = nil
        let hammer = SKLabelNode(text: "🔨")
        hammer.fontSize = layout.size * 2.2
        hammer.position = CGPoint(x: node.position.x + layout.size, y: node.position.y + layout.size * 2.4)
        hammer.zPosition = 40
        hammer.zRotation = -0.6
        fxLayer.addChild(hammer)
        let colors = node.colors.map(Theme.skColor)
        hammer.run(.sequence([
            .group([.rotate(toAngle: 0.5, duration: 0.14), .moveBy(x: -layout.size * 0.9, y: -layout.size * 1.8, duration: 0.14)]),
            .run { [weak self] in
                guard let self else { return }
                self.screenShake(amount: 4)
                self.feedback.play(.place)
                self.feedback.haptic(.heavy)
                for color in colors.prefix(4) { self.burst(at: node.position, color: color, count: 8, radius: self.layout.size * 1.6) }
                node.removeFromParent()
            },
            .wait(forDuration: 0.1),
            .fadeOut(withDuration: 0.12),
            .removeFromParent(),
        ]))
        run(.wait(forDuration: 0.42), completion: next)
    }

    // MARK: Finishing

    func finishPlayback() {
        whenFlightsLand { [weak self] in
            guard let self else { return }
            self.syncToState()
            if self.needsRebuild { self.rebuild() }
            self.refreshAccessibility()
            self.announceOutcome()
            switch self.engine.state.status {
            case .playing:
                self.phase = .idle
                self.notifyUpdate()
            case .won:
                self.phase = .finished
                self.notifyUpdate()
                self.celebrate()
            case .failed:
                self.phase = .finished
                self.notifyUpdate()
                self.lament()
            }
        }
    }

    private func whenFlightsLand(_ block: @escaping () -> Void) {
        if pendingFlights <= 0 {
            block()
        } else {
            run(.wait(forDuration: 0.05)) { [weak self] in self?.whenFlightsLand(block) }
        }
    }

    private func celebrate() {
        feedback.play(.win)
        feedback.haptic(.success)
        confetti()
        finishPending = true
        reportFinish(after: 1.1)
    }

    private func lament() {
        feedback.play(.fail)
        feedback.haptic(.warning)
        screenShake()
        finishPending = true
        reportFinish(after: 0.6)
    }

    /// Tells the delegate the level ended. Safe to call twice: only the first report goes out.
    func reportFinish(after delay: TimeInterval) {
        run(.wait(forDuration: delay)) { [weak self] in
            guard let self, self.finishPending else { return }
            self.finishPending = false
            self.gameDelegate?.gameScene(self, didFinishWith: self.engine.state.status, engine: self.engine)
        }
    }

    // MARK: Consistency

    /// Makes the node tree match the engine exactly. Animations are cosmetic; this is the safety net.
    func syncToState() {
        let board = engine.state.board
        for cell in board.cells {
            let expected = board.stack(at: cell)
            let node = boardStacks[cell]
            if let expected {
                if node?.colors == expected.tiles { continue }
                node?.removeFromParent()
                let fresh = StackNode(stack: expected, art: art)
                fresh.position = layout.center(of: cell)
                fresh.zPosition = stackZ(for: cell)
                stackLayer.addChild(fresh)
                boardStacks[cell] = fresh
            } else if let node {
                node.removeFromParent()
                boardStacks[cell] = nil
            }
        }
        for (slot, stack) in engine.state.tray.enumerated() {
            let node = trayNodes[slot]
            if let stack {
                if node?.colors == stack.tiles { continue }
                node?.removeFromParent()
                let fresh = StackNode(stack: stack, art: art)
                fresh.position = slotCenters[slot]
                trayLayer.addChild(fresh)
                trayNodes[slot] = fresh
            } else if let node {
                node.removeFromParent()
                trayNodes[slot] = nil
            }
        }
        updateHammerHighlights()
    }
}
