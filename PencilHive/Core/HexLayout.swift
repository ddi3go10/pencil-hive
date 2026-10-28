import CoreGraphics
import Foundation

/// Maps hex coordinates to screen points and back for flat-top hexes.
/// Screen space is y-up (SpriteKit), so growing `r` moves down the screen.
struct HexLayout: Equatable {
    /// Distance from a hex centre to a corner.
    var size: CGFloat
    /// Screen position of the (0, 0) cell.
    var origin: CGPoint = .zero

    static let sqrt3: CGFloat = 1.7320508075688772

    var width: CGFloat { size * 2 }
    var height: CGFloat { size * Self.sqrt3 }

    func center(of cell: HexCoord) -> CGPoint {
        CGPoint(
            x: origin.x + size * 1.5 * CGFloat(cell.q),
            y: origin.y - size * Self.sqrt3 * (CGFloat(cell.r) + CGFloat(cell.q) / 2)
        )
    }

    /// The cell whose hexagon contains `point` (cube rounding). Does not check board bounds.
    func cell(at point: CGPoint) -> HexCoord {
        // A zero size or a non-finite point has no meaningful cell; answer the origin cell
        // instead of trapping in the integer conversion below.
        guard size > 0, size.isFinite, point.x.isFinite, point.y.isFinite else { return HexCoord(q: 0, r: 0) }
        let px = point.x - origin.x
        let py = origin.y - point.y
        let qf = (2.0 / 3.0 * px) / size
        let rf = (-1.0 / 3.0 * px + Self.sqrt3 / 3.0 * py) / size
        return Self.round(q: Double(qf), r: Double(rf))
    }

    /// Nearest of `candidates` to `point`, only if it lies within `maxDistance` of its centre.
    func nearest(to point: CGPoint, among candidates: [HexCoord], maxDistance: CGFloat) -> HexCoord? {
        var best: (cell: HexCoord, distance: CGFloat)?
        for cell in candidates {
            let c = center(of: cell)
            let d = hypot(c.x - point.x, c.y - point.y)
            if d <= maxDistance, best == nil || d < best!.distance { best = (cell, d) }
        }
        return best?.cell
    }

    /// Corner points of a hexagon centred on the origin, starting at the east corner.
    func corners(scale: CGFloat = 1) -> [CGPoint] {
        (0..<6).map { i in
            let angle = CGFloat.pi / 3 * CGFloat(i)
            return CGPoint(x: cos(angle) * size * scale, y: sin(angle) * size * scale)
        }
    }

    /// Bounding box of the given cells in "unit" hex space (size == 1, origin == 0).
    static func unitBounds(of cells: [HexCoord]) -> CGRect {
        guard !cells.isEmpty else { return .zero }
        let unit = HexLayout(size: 1)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for cell in cells {
            let c = unit.center(of: cell)
            minX = min(minX, c.x - 1); maxX = max(maxX, c.x + 1)
            minY = min(minY, c.y - sqrt3 / 2); maxY = max(maxY, c.y + sqrt3 / 2)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func round(q: Double, r: Double) -> HexCoord {
        let s = -q - r
        var rq = q.rounded(), rr = r.rounded(), rs = s.rounded()
        let dq = abs(rq - q), dr = abs(rr - r), ds = abs(rs - s)
        if dq > dr && dq > ds {
            rq = -rr - rs
        } else if dr > ds {
            rr = -rq - rs
        } else {
            rs = -rq - rr
        }
        let limit = 1e9   // keeps the Int conversion safe for absurdly far points
        return HexCoord(q: Int(max(-limit, min(limit, rq))), r: Int(max(-limit, min(limit, rr))))
    }
}
