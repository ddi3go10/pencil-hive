import SpriteKit

/// Short-lived visual flourishes: particle bursts, floating score text, confetti.
extension GameScene {
    func burst(at point: CGPoint, color: SKColor, count: Int = 14, radius: CGFloat = 44, size: CGFloat = 4) {
        guard !reduceMotion else { return }
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let distance = radius * CGFloat.random(in: 0.5...1.0)
            let dot = SKShapeNode(circleOfRadius: size * CGFloat.random(in: 0.6...1.2))
            dot.fillColor = i % 3 == 0 ? .white : color
            dot.strokeColor = .clear
            dot.position = point
            dot.zPosition = 2
            fxLayer.addChild(dot)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.45)
            move.timingMode = .easeOut
            dot.run(.sequence([.group([move, .fadeOut(withDuration: 0.45), .scale(to: 0.2, duration: 0.45)]), .removeFromParent()]))
        }
    }

    func ring(at point: CGPoint, color: SKColor, radius: CGFloat) {
        guard !reduceMotion else { return }
        let ring = SKShapeNode(circleOfRadius: radius * 0.4)
        ring.strokeColor = color
        ring.fillColor = .clear
        ring.lineWidth = 4
        ring.position = point
        ring.zPosition = 1
        fxLayer.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 2.5, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
    }

    func floatText(_ text: String, at point: CGPoint, color: SKColor = .white, fontSize: CGFloat = 17) {
        let shadow = SKLabelNode(fontNamed: Theme.fontName)
        shadow.text = text
        shadow.fontSize = fontSize
        shadow.fontColor = Theme.ink
        shadow.verticalAlignmentMode = .center
        shadow.position = CGPoint(x: 1.5, y: -1.5)
        let label = SKLabelNode(fontNamed: Theme.fontName)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.verticalAlignmentMode = .center
        let holder = SKNode()
        holder.position = point
        holder.zPosition = 5
        holder.addChild(shadow)
        holder.addChild(label)
        fxLayer.addChild(holder)
        holder.setScale(0.6)
        holder.run(.sequence([
            .group([.scale(to: 1.1, duration: 0.12), .moveBy(x: 0, y: 16, duration: 0.12)]),
            .group([.moveBy(x: 0, y: 28, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent(),
        ]))
    }

    func confetti() {
        guard !reduceMotion else { return }
        let colors = TileColor.allCases.map(Theme.skColor)
        for i in 0..<70 {
            let piece = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 5...9), height: CGFloat.random(in: 8...14)), cornerRadius: 1.5)
            piece.fillColor = colors[i % colors.count]
            piece.strokeColor = .clear
            let startX = CGFloat.random(in: 0...size.width)
            piece.position = CGPoint(x: startX, y: size.height + 20)
            piece.zRotation = CGFloat.random(in: 0...(.pi))
            piece.zPosition = 3
            fxLayer.addChild(piece)
            let fall = SKAction.moveBy(x: CGFloat.random(in: -60...60), y: -(size.height + 60), duration: Double.random(in: 1.3...2.3))
            fall.timingMode = .easeIn
            piece.run(.sequence([
                .wait(forDuration: Double.random(in: 0...0.5)),
                .group([fall, .rotate(byAngle: CGFloat.random(in: -8...8), duration: 2)]),
                .removeFromParent(),
            ]))
        }
    }

    func screenShake(amount: CGFloat = 5) {
        guard !reduceMotion else { return }
        let layers = [boardLayer, stackLayer]
        for layer in layers {
            layer.run(.sequence([
                .moveBy(x: amount, y: 0, duration: 0.04), .moveBy(x: -amount * 2, y: 0, duration: 0.05),
                .moveBy(x: amount * 1.5, y: 0, duration: 0.05), .moveBy(x: -amount * 0.5, y: 0, duration: 0.04),
            ]))
        }
    }
}
