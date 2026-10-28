import SpriteKit

/// A pile of tile sprites. Tile `i` sits `i * thickness` above the base so the pile looks 3-D.
final class StackNode: SKNode {
    private let art: TileArt
    private let countLabel = SKLabelNode(fontNamed: Theme.fontName)
    private(set) var colors: [TileColor] = []
    private(set) var tiles: [SKSpriteNode] = []

    init(stack: TileStack, art: TileArt) {
        self.art = art
        super.init()
        countLabel.fontSize = art.hexSize * 0.36
        countLabel.verticalAlignmentMode = .center
        countLabel.horizontalAlignmentMode = .center
        addChild(countLabel)
        for color in stack.tiles { append(color) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var height: Int { tiles.count }
    var topColor: TileColor? { colors.last }

    func localPosition(ofTile index: Int) -> CGPoint {
        CGPoint(x: 0, y: CGFloat(index) * art.thickness)
    }

    /// Where the next tile on top of the pile would sit.
    var nextTilePosition: CGPoint { localPosition(ofTile: tiles.count) }

    func append(_ color: TileColor) {
        let sprite = art.tileSprite(color)
        adopt(sprite, color: color)
    }

    /// Takes ownership of an existing tile sprite and settles it on top of the pile.
    func adopt(_ sprite: SKSpriteNode, color: TileColor) {
        sprite.removeAllActions()
        if sprite.parent !== self { sprite.removeFromParent(); addChild(sprite) }
        sprite.setScale(1)
        sprite.alpha = 1
        sprite.zRotation = 0
        sprite.position = localPosition(ofTile: tiles.count)
        sprite.zPosition = CGFloat(tiles.count)
        tiles.append(sprite)
        colors.append(color)
        updateCount()
    }

    /// Removes the top `count` tiles from the pile and returns them (bottom-most first), still
    /// parented here so the caller can convert their positions before moving them elsewhere.
    func detachTop(_ count: Int) -> [(sprite: SKSpriteNode, color: TileColor)] {
        let count = min(count, tiles.count)
        let start = tiles.count - count
        let removed = Array(zip(tiles[start...], colors[start...])).map { (sprite: $0, color: $1) }
        tiles.removeLast(count)
        colors.removeLast(count)
        updateCount()
        return removed
    }

    private func updateCount() {
        countLabel.text = art.showsSymbols || tiles.isEmpty ? nil : "\(TileStack(colors).topRunLength)"
        countLabel.fontColor = topColor.map { Theme.skColor($0).darkened(by: 0.48) }
        countLabel.position = CGPoint(x: 0, y: CGFloat(max(0, tiles.count - 1)) * art.thickness)
        countLabel.zPosition = CGFloat(tiles.count) + 1
    }

    func removeAllTiles() {
        tiles.forEach { $0.removeFromParent() }
        tiles.removeAll()
        colors.removeAll()
        updateCount()
    }
}
