import CoreGraphics
import SpriteKit

/// Colours and small helpers shared by the SpriteKit layer.
enum Theme {
    static let backgroundTop = SKColor(red: 1, green: 247.0 / 255, blue: 220.0 / 255, alpha: 1)
    static let backgroundBottom = SKColor(red: 0.99, green: 0.88, blue: 0.62, alpha: 1)
    static let cellFill = SKColor(red: 233.0 / 255, green: 220.0 / 255, blue: 188.0 / 255, alpha: 1)
    static let cellRim = SKColor(red: 0.80, green: 0.60, blue: 0.36, alpha: 1)
    static let ink = SKColor(red: 0.27, green: 0.18, blue: 0.12, alpha: 1)
    static let fontName = "AvenirNext-Heavy"

    static func cgColor(_ color: TileColor, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(color.rgb.r), green: CGFloat(color.rgb.g), blue: CGFloat(color.rgb.b), alpha: alpha)
    }

    static func skColor(_ color: TileColor) -> SKColor {
        SKColor(red: CGFloat(color.rgb.r), green: CGFloat(color.rgb.g), blue: CGFloat(color.rgb.b), alpha: 1)
    }

    /// Parses `#RRGGBB`; falls back to white.
    static func skColor(hex: String) -> SKColor {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return .white }
        return SKColor(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

extension CGColor {
    /// Blend toward white (`t` > 0) or black (`t` < 0).
    func tinted(_ t: CGFloat) -> CGColor {
        let c = components ?? [0, 0, 0, 1]
        let target: CGFloat = t >= 0 ? 1 : 0
        let amount = abs(t)
        let r = c[0] + (target - c[0]) * amount
        let g = (c.count > 2 ? c[1] : c[0]) + (target - (c.count > 2 ? c[1] : c[0])) * amount
        let b = (c.count > 2 ? c[2] : c[0]) + (target - (c.count > 2 ? c[2] : c[0])) * amount
        return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

struct SceneInsets: Equatable {
    /// Space at the top reserved for the SwiftUI HUD within the safe area.
    var top: CGFloat = 100
    /// Space at the bottom reserved for the booster bar within the safe area.
    var bottom: CGFloat = 84
}

extension SKColor {
    func darkened(by amount: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r * (1 - amount), green: g * (1 - amount), blue: b * (1 - amount), alpha: a)
    }

    func blended(with other: SKColor, amount: CGFloat) -> SKColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return SKColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: a1 + (a2 - a1) * amount)
    }
}
