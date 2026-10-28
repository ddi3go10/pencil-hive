import CoreGraphics
import Foundation

/// A drawable shape in a unit square. `(0, 0)` is the top-left corner and `y` grows downward,
/// like SVG. The renderer scales it to the artwork panel.
enum ArtShape: Hashable, Codable {
    case polygon(points: [CGPoint])
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
    case rect(x: Double, y: Double, w: Double, h: Double, radius: Double)

    private enum CodingKeys: String, CodingKey { case type, points, cx, cy, rx, ry, x, y, w, h, radius }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "polygon":
            let raw = try c.decode([[Double]].self, forKey: .points)
            guard raw.allSatisfy({ $0.count == 2 }) else {
                throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "Points must be [x, y] pairs")
            }
            self = .polygon(points: raw.map { CGPoint(x: $0[0], y: $0[1]) })
        case "ellipse":
            self = .ellipse(
                cx: try c.decode(Double.self, forKey: .cx), cy: try c.decode(Double.self, forKey: .cy),
                rx: try c.decode(Double.self, forKey: .rx), ry: try c.decode(Double.self, forKey: .ry))
        case "rect":
            self = .rect(
                x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y),
                w: try c.decode(Double.self, forKey: .w), h: try c.decode(Double.self, forKey: .h),
                radius: try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown shape type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .polygon(let points):
            try c.encode("polygon", forKey: .type)
            try c.encode(points.map { [Double($0.x), Double($0.y)] }, forKey: .points)
        case let .ellipse(cx, cy, rx, ry):
            try c.encode("ellipse", forKey: .type)
            try c.encode(cx, forKey: .cx); try c.encode(cy, forKey: .cy)
            try c.encode(rx, forKey: .rx); try c.encode(ry, forKey: .ry)
        case let .rect(x, y, w, h, radius):
            try c.encode("rect", forKey: .type)
            try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
            try c.encode(w, forKey: .w); try c.encode(h, forKey: .h)
            try c.encode(radius, forKey: .radius)
        }
    }

    /// Centre of the shape's bounding box in unit space.
    var center: CGPoint {
        switch self {
        case .polygon(let points):
            guard !points.isEmpty else { return .zero }
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
        case let .ellipse(cx, cy, _, _):
            return CGPoint(x: cx, y: cy)
        case let .rect(x, y, w, h, _):
            return CGPoint(x: x + w / 2, y: y + h / 2)
        }
    }
}

/// One area of the illustration that a pencil of `color` fills in.
struct ArtRegion: Hashable, Codable, Identifiable {
    let id: Int
    let color: TileColor
    let shape: ArtShape
}

/// An original illustration that is coloured in one pencil at a time.
/// The regions are the level goal: finish them all to win.
struct Artwork: Hashable, Codable {
    let name: String
    /// Paper colour as `#RRGGBB`.
    let paper: String
    let regions: [ArtRegion]
    /// Thin outline-only details drawn on top (windows, whiskers, ...).
    let lineArt: [ArtShape]

    init(name: String, paper: String, regions: [ArtRegion], lineArt: [ArtShape] = []) {
        self.name = name
        self.paper = paper
        self.regions = regions
        self.lineArt = lineArt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        paper = try c.decodeIfPresent(String.self, forKey: .paper) ?? "#FFF8E6"
        regions = try c.decode([ArtRegion].self, forKey: .regions)
        lineArt = try c.decodeIfPresent([ArtShape].self, forKey: .lineArt) ?? []
    }

    /// How many regions each colour needs, i.e. the per-colour pencil goals.
    var goals: [TileColor: Int] {
        regions.reduce(into: [:]) { $0[$1.color, default: 0] += 1 }
    }

    func region(id: Int) -> ArtRegion? { regions.first { $0.id == id } }
}
