import Foundation

/// The pencil colours. Raw values are used in level JSON.
enum TileColor: String, Codable, CaseIterable, Hashable, Comparable {
    case coral, amber, lemon, mint, sky, indigo, violet, rose

    /// sRGB components in 0...1, shared by SpriteKit and SwiftUI.
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .coral: return (0.93, 0.29, 0.27)
        case .amber: return (0.98, 0.60, 0.13)
        case .lemon: return (0.99, 0.84, 0.22)
        case .mint: return (0.27, 0.76, 0.43)
        case .sky: return (0.25, 0.62, 0.96)
        case .indigo: return (0.35, 0.37, 0.82)
        case .violet: return (0.67, 0.37, 0.86)
        case .rose: return (0.97, 0.43, 0.69)
        }
    }

    var displayName: String { rawValue.capitalized }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: TileColor, rhs: TileColor) -> Bool { lhs.order < rhs.order }
}
