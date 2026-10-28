import CoreGraphics
import Foundation

/// A shape printed on every tile of a colour, so colours can be told apart without seeing them.
enum TileSymbol: String, CaseIterable, Hashable {
    case circle, triangle, square, diamond, star, plus, cross, ring

    var displayName: String { rawValue }

    /// The outline, centred in `rect`. `ring` is a circle drawn with an even-odd hole.
    func path(in rect: CGRect) -> CGPath {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let path = CGMutablePath()
        func polygon(_ points: [CGPoint]) {
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
        switch self {
        case .circle:
            path.addEllipse(in: CGRect(x: c.x - r * 0.9, y: c.y - r * 0.9, width: r * 1.8, height: r * 1.8))
        case .ring:
            path.addEllipse(in: CGRect(x: c.x - r * 0.9, y: c.y - r * 0.9, width: r * 1.8, height: r * 1.8))
            path.addEllipse(in: CGRect(x: c.x - r * 0.48, y: c.y - r * 0.48, width: r * 0.96, height: r * 0.96))
        case .triangle:
            polygon([CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r * 0.95, y: c.y - r * 0.7), CGPoint(x: c.x + r * 0.95, y: c.y - r * 0.7)])
        case .square:
            path.addRect(CGRect(x: c.x - r * 0.78, y: c.y - r * 0.78, width: r * 1.56, height: r * 1.56))
        case .diamond:
            polygon([CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + r * 0.85, y: c.y), CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - r * 0.85, y: c.y)])
        case .star:
            polygon((0..<10).map { i in
                let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let radius = i % 2 == 0 ? r : r * 0.42
                return CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            })
        case .plus:
            let t = r * 0.36
            polygon([
                CGPoint(x: c.x - t, y: c.y + r), CGPoint(x: c.x + t, y: c.y + r), CGPoint(x: c.x + t, y: c.y + t),
                CGPoint(x: c.x + r, y: c.y + t), CGPoint(x: c.x + r, y: c.y - t), CGPoint(x: c.x + t, y: c.y - t),
                CGPoint(x: c.x + t, y: c.y - r), CGPoint(x: c.x - t, y: c.y - r), CGPoint(x: c.x - t, y: c.y - t),
                CGPoint(x: c.x - r, y: c.y - t), CGPoint(x: c.x - r, y: c.y + t), CGPoint(x: c.x - t, y: c.y + t),
            ])
        case .cross:
            let t = r * 0.3, d = r * 0.92
            polygon([
                CGPoint(x: c.x - d + t, y: c.y + d), CGPoint(x: c.x, y: c.y + t * 1.2), CGPoint(x: c.x + d - t, y: c.y + d),
                CGPoint(x: c.x + d, y: c.y + d - t), CGPoint(x: c.x + t * 1.2, y: c.y), CGPoint(x: c.x + d, y: c.y - d + t),
                CGPoint(x: c.x + d - t, y: c.y - d), CGPoint(x: c.x, y: c.y - t * 1.2), CGPoint(x: c.x - d + t, y: c.y - d),
                CGPoint(x: c.x - d, y: c.y - d + t), CGPoint(x: c.x - t * 1.2, y: c.y), CGPoint(x: c.x - d, y: c.y + d - t),
            ])
        }
        return path
    }

    /// Whether the outline has a hole that must be cut with the even-odd rule.
    var usesEvenOddFill: Bool { self == .ring }
}

extension TileColor {
    /// One symbol per colour, fixed so a player learns them.
    var symbol: TileSymbol {
        switch self {
        case .coral: return .circle
        case .amber: return .triangle
        case .lemon: return .square
        case .mint: return .diamond
        case .sky: return .star
        case .indigo: return .plus
        case .violet: return .cross
        case .rose: return .ring
        }
    }

    /// True when the colour is light enough that a dark symbol reads better than a white one.
    var prefersDarkSymbol: Bool {
        0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b > 0.6
    }
}
