import SpriteKit

#if canImport(UIKit)
import UIKit

/// A tappable spot on the board or tray that VoiceOver can read and activate.
private final class BoardAccessibilityElement: UIAccessibilityElement {
    var onActivate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { onActivate?() ?? false }
}

// MARK: VoiceOver
//
// The board is drawn with SpriteKit, which VoiceOver cannot see, so the scene publishes its own
// accessibility elements. Dragging is replaced by two double taps: pick a stack, then an empty cell.

extension GameScene {
    static func systemReduceMotion() -> Bool { UIAccessibility.isReduceMotionEnabled }

    func refreshAccessibility() {
        guard let view else { return }
        var elements: [UIAccessibilityElement] = []

        for slot in engine.state.tray.indices {
            guard let stack = engine.state.tray[slot], slotCenters.indices.contains(slot) else { continue }
            let element = BoardAccessibilityElement(accessibilityContainer: view)
            element.accessibilityLabel = "Stack \(slot + 1): \(AccessibilityText.stack(stack))"
            element.accessibilityHint = hammerMode
                ? "Double tap to cancel the hammer and pick up this stack."
                : "Double tap to pick up this stack, then double tap an empty cell to place it."
            element.accessibilityTraits = selectedSlot == slot ? [.button, .selected] : .button
            element.accessibilityFrame = screenFrame(around: slotCenters[slot], halfSize: layout.size * 1.6, in: view)
            element.onActivate = { [weak self] in self?.selectSlot(slot) ?? false }
            elements.append(element)
        }

        let positions = AccessibilityText.positions(of: engine.state.board.cells)
        for cell in engine.state.board.cells.sorted(by: { ($0.r, $0.q) < ($1.r, $1.q) }) {
            guard let place = positions[cell] else { continue }
            let element = BoardAccessibilityElement(accessibilityContainer: view)
            let stack = engine.state.board.stack(at: cell)
            element.accessibilityLabel = AccessibilityText.cell(row: place.row, column: place.column, stack: stack)
            if hammerMode, stack != nil {
                element.accessibilityHint = "Double tap to smash this stack with the hammer."
            }
            element.accessibilityTraits = .button
            element.accessibilityFrame = screenFrame(around: layout.center(of: cell), halfSize: layout.size * 0.9, in: view)
            element.onActivate = { [weak self] in self?.activate(cell: cell) ?? false }
            elements.append(element)
        }
        view.accessibilityElements = elements
    }

    private func screenFrame(around point: CGPoint, halfSize: CGFloat, in view: SKView) -> CGRect {
        let centre = convertPoint(toView: point)
        let rect = CGRect(x: centre.x - halfSize, y: centre.y - halfSize, width: halfSize * 2, height: halfSize * 2)
        return UIAccessibility.convertToScreenCoordinates(rect, in: view)
    }

    private func selectSlot(_ slot: Int) -> Bool {
        guard phase == .idle, !inputBlocked, engine.state.status.isPlaying, engine.state.tray.indices.contains(slot), engine.state.tray[slot] != nil else { return false }
        hammerMode = false
        selectedSlot = selectedSlot == slot ? nil : slot
        refreshAccessibility()
        announce(selectedSlot == nil ? "Stack \(slot + 1) put down." : "Stack \(slot + 1) picked up. Choose an empty cell.")
        return true
    }

    private func activate(cell: HexCoord) -> Bool {
        guard phase == .idle, !inputBlocked, engine.state.status.isPlaying else { return false }
        if hammerMode {
            guard engine.state.board.stack(at: cell) != nil else { announce("Nothing to smash here."); return false }
            smash(cell)
            return true
        }
        guard let slot = selectedSlot, let node = trayNodes[slot] else {
            announce("Pick up a stack first.")
            return false
        }
        guard engine.canPlace(slot: slot, at: cell) else {
            announce("That cell is taken. Choose an empty cell.")
            return false
        }
        selectedSlot = nil
        commitPlacement(slot: slot, cell: cell, node: node)
        return true
    }

    func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// Speaks what the last move did once its animation has settled.
    func announceOutcome() {
        switch engine.state.status {
        case .won(let stars): announce(AccessibilityText.win(stars: stars, score: engine.state.score))
        case .failed(let reason): announce(AccessibilityText.fail(reason))
        case .playing:
            if let text = pendingAnnouncement { announce(text) }
        }
        pendingAnnouncement = nil
    }
}
#else
extension GameScene {
    static func systemReduceMotion() -> Bool { false }
    func refreshAccessibility() {}
    func announce(_ text: String) {}
    func announceOutcome() {}
}
#endif
