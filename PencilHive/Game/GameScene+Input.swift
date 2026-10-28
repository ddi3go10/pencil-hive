import SpriteKit

// MARK: Pointer handling
//
// Touch (iOS) and mouse (macOS, used by the preview harness) both funnel into these three methods.

extension GameScene {
    #if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Follow a single finger; extra fingers must not start, move or end the drag.
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        pointerDown(at: touch.location(in: self))
        if phase != .dragging { activeTouch = nil }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = activeTouch, let touch = touches.first(where: { $0 === tracked }) else { return }
        pointerMoved(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = activeTouch, let touch = touches.first(where: { $0 === tracked }) else { return }
        activeTouch = nil
        pointerUp(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = activeTouch, touches.contains(where: { $0 === tracked }) else { return }
        activeTouch = nil
        pointerCancelled()
    }
    #else
    override func mouseDown(with event: NSEvent) { pointerDown(at: event.location(in: self)) }
    override func mouseDragged(with event: NSEvent) { pointerMoved(to: event.location(in: self)) }
    override func mouseUp(with event: NSEvent) { pointerUp(at: event.location(in: self)) }
    #endif

    /// The top face follows 38 points above the finger so the stack stays visible above a thumb.
    var dragLift: CGFloat { 38 }

    func pointerDown(at point: CGPoint) {
        guard phase == .idle, !inputBlocked, engine.state.status.isPlaying else { return }

        if hammerMode {
            if let cell = boardCell(atRenderedStackFace: point) {
                smash(cell)
            } else {
                hammerMode = false
            }
            return
        }

        // Pick the tray stack closest to the touch.
        var best: (slot: Int, distance: CGFloat)?
        for (slot, node) in trayNodes {
            let centre = CGPoint(x: node.position.x, y: node.position.y + CGFloat(max(0, node.height - 1)) * art.thickness / 2)
            let d = hypot(centre.x - point.x, centre.y - point.y)
            if d < layout.size * 1.7, best == nil || d < best!.distance { best = (slot, d) }
        }
        guard let best, let node = trayNodes[best.slot] else { return }

        node.removeFromParent()
        node.zPosition = 0
        dragLayer.addChild(node)
        node.removeAllActions()
        let lifted = CGPoint(x: point.x, y: point.y + dragLift)
        node.setScale(reduceMotion ? 1 : 1.1)
        node.position = CGPoint(x: lifted.x, y: lifted.y - node.localPosition(ofTile: max(0, node.height - 1)).y * node.yScale)
        drag = DragState(slot: best.slot, node: node, target: nil)
        phase = .dragging
        feedback.play(.pickup)
        feedback.haptic(.light)
    }

    /// Finds the frontmost rendered hex face under the pointer, respecting board draw order.
    /// Stack height moves visible faces away from their board coordinate, so cell-center distance
    /// can select a different stack than the one the player tapped.
    private func boardCell(atRenderedStackFace point: CGPoint) -> HexCoord? {
        for (cell, node) in boardStacks.sorted(by: { $0.value.zPosition > $1.value.zPosition }) {
            guard engine.state.board.stack(at: cell) != nil else { continue }
            let local = node.convert(point, from: self)
            for tile in node.tiles.reversed() {
                let dx = abs(local.x - tile.position.x)
                let dy = abs(local.y - tile.position.y)
                let radius = art.hexSize * 0.94
                // Exclude transparent corners in the tile texture's rectangular sprite bounds.
                if dx <= radius, dy <= radius * HexLayout.sqrt3 / 2,
                   dy + HexLayout.sqrt3 * dx <= HexLayout.sqrt3 * radius {
                    return cell
                }
            }
        }
        return nil
    }

    func pointerMoved(to point: CGPoint) {
        guard phase == .dragging, var state = drag else { return }
        let lifted = CGPoint(x: point.x, y: point.y + dragLift)
        state.node.removeAction(forKey: "follow")
        state.node.position = CGPoint(x: lifted.x, y: lifted.y - state.node.localPosition(ofTile: max(0, state.node.height - 1)).y * state.node.yScale)
        let target = layout.nearest(to: lifted, among: engine.legalCells, maxDistance: layout.size * 1.25)
        if target != state.target {
            state.target = target
            drag = state
            showHighlight(at: target)
            if target != nil { feedback.haptic(.light) }
        }
    }

    func pointerUp(at point: CGPoint) {
        guard phase == .dragging else { return }
        pointerMoved(to: point)
        guard let state = drag else { return }
        drag = nil
        showHighlight(at: nil)
        state.node.removeAllActions()
        if let target = state.target, engine.canPlace(slot: state.slot, at: target) {
            commitPlacement(slot: state.slot, cell: target, node: state.node)
        } else {
            returnToTray(slot: state.slot, node: state.node)
        }
    }

    func pointerCancelled() {
        guard phase == .dragging, let state = drag else { return }
        drag = nil
        showHighlight(at: nil)
        returnToTray(slot: state.slot, node: state.node)
    }

    func showHighlight(at cell: HexCoord?) {
        highlight?.removeFromParent()
        highlight = nil
        guard let cell else { return }
        let glow = art.glowSprite()
        glow.position = layout.center(of: cell)
        glow.zPosition = 5
        boardLayer.addChild(glow)
        if !reduceMotion {
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.3), .fadeAlpha(to: 1, duration: 0.3)])))
        }
        highlight = glow
    }

    private func returnToTray(slot: Int, node: StackNode) {
        if reduceMotion {
            node.removeAllActions()
            node.removeFromParent()
            node.position = slotCenters[slot]
            node.setScale(1)
            trayLayer.addChild(node)
            node.alpha = 0
            node.run(.fadeIn(withDuration: 0.15))
            phase = .idle
            if needsRebuild { rebuild() }
            return
        }
        phase = .animating
        feedback.play(.error)
        node.run(.group([
            .move(to: slotCenters[slot], duration: 0.18),
            .scale(to: 1, duration: 0.18),
        ])) { [weak self] in
            guard let self else { return }
            node.removeFromParent()
            node.position = self.slotCenters[slot]
            self.trayLayer.addChild(node)
            self.phase = .idle
            // A resize that arrived while the stack was returning has been waiting for this moment.
            if self.needsRebuild { self.rebuild() }
        }
    }
}
