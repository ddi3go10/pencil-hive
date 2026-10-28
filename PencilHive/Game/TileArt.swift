import CoreGraphics
import SpriteKit

/// Draws and caches the textures for tiles, empty cells and pencils with Core Graphics, so the
/// scene is made of a few cheap sprites instead of hundreds of shape nodes.
final class TileArt {
    /// Corner radius of a board hex in points.
    let hexSize: CGFloat
    /// Whether tiles carry their colour's symbol.
    let showsSymbols: Bool
    /// Visible thickness of one tile in points.
    let thickness: CGFloat
    private let pixelScale: CGFloat = 3
    private var tileTextures: [TileColor: Image] = [:]
    private var pencilTextures: [TileColor: Image] = [:]
    private lazy var cellImage: Image = renderCell()
    private lazy var glowImage: Image = renderGlow()

    /// A rendered texture together with its size in points (the texture itself is in pixels).
    struct Image {
        let texture: SKTexture
        let size: CGSize

        func sprite() -> SKSpriteNode {
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = size
            return sprite
        }
    }

    init(hexSize: CGFloat, showsSymbols: Bool = false) {
        self.hexSize = hexSize
        self.showsSymbols = showsSymbols
        self.thickness = hexSize * 0.16
    }

    private var drawRadius: CGFloat { hexSize * 0.94 }

    // MARK: Sprites

    func tileSprite(_ color: TileColor) -> SKSpriteNode {
        let image = tileTextures[color] ?? renderTile(color)
        tileTextures[color] = image
        let sprite = image.sprite()
        // The tile's face centre sits `thickness + padding` above the texture bottom.
        let pad = hexSize * 0.08
        sprite.anchorPoint = CGPoint(x: 0.5, y: (thickness + pad + drawRadius * HexLayout.sqrt3 / 2) / sprite.size.height)
        return sprite
    }

    func cellSprite() -> SKSpriteNode { cellImage.sprite() }

    func glowSprite() -> SKSpriteNode { glowImage.sprite() }

    func pencilSprite(_ color: TileColor) -> SKSpriteNode {
        let image = pencilTextures[color] ?? renderPencil(color)
        pencilTextures[color] = image
        return image.sprite()
    }

    // MARK: Rendering

    private func render(size: CGSize, draw: (CGContext) -> Void) -> Image {
        let width = Int((size.width * pixelScale).rounded(.up))
        let height = Int((size.height * pixelScale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Image(texture: SKTexture(), size: size) }
        context.scaleBy(x: pixelScale, y: pixelScale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        draw(context)
        guard let image = context.makeImage() else { return Image(texture: SKTexture(), size: size) }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return Image(texture: texture, size: size)
    }

    private func hexPath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = CGFloat.pi / 3 * CGFloat(i)
            let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    private func renderTile(_ color: TileColor) -> Image {
        let r = drawRadius
        let pad = hexSize * 0.08
        let size = CGSize(width: r * 2 + pad * 2, height: r * HexLayout.sqrt3 + thickness + pad * 2)
        let base = Theme.cgColor(color)
        return render(size: size) { ctx in
            let faceCenter = CGPoint(x: size.width / 2, y: thickness + pad + r * HexLayout.sqrt3 / 2)
            // Sweep a dark hex downward to build the side wall.
            let steps = max(2, Int(thickness * pixelScale))
            for i in stride(from: steps, through: 0, by: -1) {
                let offset = thickness * CGFloat(i) / CGFloat(steps)
                ctx.addPath(hexPath(center: CGPoint(x: faceCenter.x, y: faceCenter.y - offset), radius: r))
                ctx.setFillColor(base.tinted(-0.22))
                ctx.fillPath()
            }
            ctx.addPath(hexPath(center: faceCenter, radius: r))
            ctx.setFillColor(base)
            ctx.fillPath()
            ctx.addPath(hexPath(center: faceCenter, radius: r - 0.6))
            ctx.setStrokeColor(base.tinted(0.45))
            ctx.setLineWidth(1.4)
            ctx.strokePath()
            ctx.addPath(hexPath(center: faceCenter, radius: r * 0.66))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.96, blue: 0.81, alpha: 1))
            ctx.fillPath()
            ctx.addPath(hexPath(center: faceCenter, radius: r * 0.66))
            ctx.setStrokeColor(base.tinted(-0.12))
            ctx.setLineWidth(0.8)
            ctx.strokePath()
            ctx.addPath(hexPath(center: faceCenter, radius: r * 0.46))
            ctx.setFillColor(base)
            ctx.fillPath()
            if showsSymbols {
                let side = r * 0.62
                let box = CGRect(x: faceCenter.x - side / 2, y: faceCenter.y - side / 2, width: side, height: side)
                ctx.addPath(color.symbol.path(in: box))
                ctx.setFillColor(color.prefersDarkSymbol
                    ? CGColor(srgbRed: 0.27, green: 0.18, blue: 0.12, alpha: 0.9)
                    : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
                if color.symbol.usesEvenOddFill { ctx.fillPath(using: .evenOdd) } else { ctx.fillPath() }
            } else {
                // Soft gloss. It is left off when a symbol takes the middle of the face.
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28))
                ctx.fillEllipse(in: CGRect(x: faceCenter.x - r * 0.42, y: faceCenter.y + r * 0.18, width: r * 0.5, height: r * 0.22))
            }
        }
    }

    private func renderCell() -> Image {
        let r = hexSize * 0.97
        let size = CGSize(width: r * 2 + 4, height: r * HexLayout.sqrt3 + 4)
        return render(size: size) { ctx in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.addPath(hexPath(center: center, radius: r))
            ctx.setFillColor(Theme.cellFill.cgColor)
            ctx.fillPath()
        }
    }

    private func renderGlow() -> Image {
        let r = hexSize * 1.02
        let size = CGSize(width: r * 2 + 8, height: r * HexLayout.sqrt3 + 8)
        return render(size: size) { ctx in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.addPath(hexPath(center: center, radius: r))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.83, blue: 0.13, alpha: 0.6))
            ctx.fillPath()
            ctx.addPath(hexPath(center: center, radius: r - 1))
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.98, blue: 0.85, alpha: 1))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
    }

    /// A pencil pointing right (+x) so `orientToPath` flies it tip first.
    private func renderPencil(_ color: TileColor) -> Image {
        let length = hexSize * 2.9
        let width = hexSize * 0.7
        let size = CGSize(width: length + 4, height: width + 4)
        let base = Theme.cgColor(color)
        return render(size: size) { ctx in
            let y0: CGFloat = 2, x0: CGFloat = 2
            let eraser = width * 0.55, ferrule = width * 0.5, tip = width * 1.05
            let bodyStart = x0 + eraser + ferrule
            let bodyEnd = x0 + length - tip

            func fill(_ rect: CGRect, _ color: CGColor, radius: CGFloat = 0) {
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.setFillColor(color)
                ctx.fillPath()
            }
            // Eraser and ferrule.
            fill(CGRect(x: x0, y: y0, width: eraser + 3, height: width), CGColor(srgbRed: 0.98, green: 0.62, blue: 0.70, alpha: 1), radius: width * 0.3)
            fill(CGRect(x: x0 + eraser, y: y0, width: ferrule, height: width), CGColor(srgbRed: 0.78, green: 0.80, blue: 0.84, alpha: 1))
            fill(CGRect(x: x0 + eraser + ferrule * 0.3, y: y0, width: ferrule * 0.14, height: width), CGColor(srgbRed: 0.55, green: 0.58, blue: 0.64, alpha: 1))
            // Painted body with a light and a dark band for volume.
            fill(CGRect(x: bodyStart, y: y0, width: bodyEnd - bodyStart + 1, height: width), base)
            fill(CGRect(x: bodyStart, y: y0 + width * 0.58, width: bodyEnd - bodyStart + 1, height: width * 0.42), base.tinted(0.3))
            fill(CGRect(x: bodyStart, y: y0, width: bodyEnd - bodyStart + 1, height: width * 0.2), base.tinted(-0.25))
            // Wood cone and lead.
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: bodyEnd, y: y0))
            cone.addLine(to: CGPoint(x: bodyEnd, y: y0 + width))
            cone.addLine(to: CGPoint(x: x0 + length, y: y0 + width / 2))
            cone.closeSubpath()
            ctx.addPath(cone)
            ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.80, blue: 0.58, alpha: 1))
            ctx.fillPath()
            let lead = CGMutablePath()
            lead.move(to: CGPoint(x: x0 + length - tip * 0.42, y: y0 + width / 2 - width * 0.16))
            lead.addLine(to: CGPoint(x: x0 + length - tip * 0.42, y: y0 + width / 2 + width * 0.16))
            lead.addLine(to: CGPoint(x: x0 + length, y: y0 + width / 2))
            lead.closeSubpath()
            ctx.addPath(lead)
            ctx.setFillColor(base.tinted(-0.1))
            ctx.fillPath()
        }
    }
}
