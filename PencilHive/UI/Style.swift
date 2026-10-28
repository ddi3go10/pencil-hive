import SwiftUI

enum Palette {
    static let cream = Color(red: 1, green: 247.0 / 255, blue: 220.0 / 255)
    static let sand = Color(red: 0.99, green: 0.88, blue: 0.62)
    static let wood = Color(red: 0.62, green: 0.41, blue: 0.23)
    static let ink = Color(red: 0.27, green: 0.18, blue: 0.12)
    static let panel = Color(red: 1.00, green: 0.99, blue: 0.93)
    static let green = Color(red: 0.27, green: 0.76, blue: 0.43)
    static let blue = Color(red: 0.25, green: 0.62, blue: 0.96)
    static let coral = Color(red: 0.93, green: 0.29, blue: 0.27)
    static let gold = Color(red: 0.99, green: 0.78, blue: 0.15)
}

extension TileColor {
    var swiftUIColor: Color { Color(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height / HexLayout.sqrt3)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for i in 0..<6 {
            let angle = CGFloat.pi / 3 * CGFloat(i)
            let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// The game's rounded font at a base size that grows with the player's Dynamic Type setting.
private struct RoundedFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
    }
}

extension View {
    func roundedFont(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> some View {
        modifier(RoundedFont(size: size, weight: weight))
    }
}

/// A tile symbol as a SwiftUI shape, for the HUD chips.
struct SymbolShape: Shape {
    let symbol: TileSymbol

    func path(in rect: CGRect) -> Path {
        // Core Graphics paths grow upwards; flip so the symbols are not upside down on screen.
        var flip = CGAffineTransform(translationX: 0, y: rect.height).scaledBy(x: 1, y: -1)
        let cgPath = symbol.path(in: CGRect(origin: .zero, size: rect.size))
        return Path(cgPath.copy(using: &flip) ?? cgPath).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A fat, tappable button with a darker "ledge" like the game's tiles.
struct ChunkyButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = Palette.green
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .roundedFont(compact ? 16 : 20, .heavy)
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 16 : 26)
            .padding(.vertical, compact ? 9 : 14)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.28), radius: 0, x: 0, y: configuration.isPressed ? 1 : 4)
            )
            .offset(y: configuration.isPressed && !reduceMotion ? 3 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct Pill: View {
    let icon: String
    let text: String
    var tint: Color = Palette.ink

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13, weight: .heavy))
            Text(text).roundedFont(16, .heavy).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.panel.opacity(0.92)))
        .overlay(Capsule().strokeBorder(Palette.wood.opacity(0.35), lineWidth: 1.5))
    }
}

struct StarRow: View {
    let earned: Int
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { index in
                Image(systemName: index <= earned ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundColor(index <= earned ? Palette.gold : Palette.wood.opacity(0.35))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned) of 3 stars")
    }
}

/// The game logo: a hex tile with a pencil through it.
struct LogoMark: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            HexagonShape().fill(Palette.wood).offset(y: size * 0.06)
            HexagonShape().fill(TileColor.amber.swiftUIColor)
            HexagonShape().fill(TileColor.lemon.swiftUIColor.opacity(0.9)).scaleEffect(0.66)
            Capsule()
                .fill(LinearGradient(colors: [TileColor.coral.swiftUIColor, TileColor.rose.swiftUIColor], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.9, height: size * 0.2)
                .rotationEffect(.degrees(-40))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
        }
        .frame(width: size, height: size)
    }
}

/// Progress is driven by pencil landings, not the engine's already-computed end state.
struct PencilProgressView: View {
    let done: Int
    let total: Int
    let colors: [TileColor]

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            HStack(spacing: 0) {
                UnevenEraser().fill(Color(red: 0.96, green: 0.46, blue: 0.59)).frame(width: 16)
                Rectangle().fill(Color(red: 0.68, green: 0.71, blue: 0.74)).frame(width: 9)
                    .overlay(Rectangle().fill(Color.white.opacity(0.4)).frame(width: 2))
                ZStack {
                    Rectangle().fill(Palette.wood.opacity(0.3))
                    HStack(spacing: 1) {
                        ForEach(0..<max(1, total), id: \.self) { index in
                            Rectangle().fill(index < colors.count ? colors[index].swiftUIColor : Color.clear)
                        }
                    }
                    Text("\(done)/\(total)")
                        .roundedFont(17, .black).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .foregroundColor(.white)
                        .shadow(color: Palette.ink.opacity(0.4), radius: 1, y: 1)
                }
                PencilTip().fill(Color(red: 0.89, green: 0.70, blue: 0.43)).frame(width: height * 0.65)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 4).padding(.horizontal, 25)
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct PencilTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: 0, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct UnevenEraser: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 6)
    }
}

/// Original vector illustration, shared by rewards and the collection.
struct ArtworkThumbnail: View {
    let artwork: Artwork
    var completed = false
    var animateReveal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedCount: Int?
    @State private var revealScale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 150, y: size.height / 100)
            for (index, region) in artwork.regions.enumerated() {
                let path = drawingPath(region.shape)
                let filled = completed && (revealedCount == nil || index < revealedCount!)
                context.fill(path, with: .color(region.color.swiftUIColor.opacity(filled ? 1 : 0.16)))
                context.stroke(path, with: .color(Palette.ink.opacity(0.55)), lineWidth: 0.7)
            }
            for shape in artwork.lineArt {
                context.stroke(drawingPath(shape), with: .color(Palette.ink), lineWidth: 0.8)
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
        .background(Color(uiColor: Theme.skColor(hex: artwork.paper)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.wood))
        .scaleEffect(revealScale)
        .overlay(alignment: .bottomTrailing) {
            if completed && (revealedCount == nil || revealedCount! >= artwork.regions.count) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Palette.green).background(Circle().fill(.white))
                    .padding(3)
            }
        }
        .onAppear {
            guard completed, animateReveal, !reduceMotion, !artwork.regions.isEmpty else { return }
            revealedCount = 0
            revealScale = 0.95
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                revealScale = 1
            }
            let total = artwork.regions.count
            let step = min(0.055, 0.4 / Double(total))
            for i in 1...total {
                DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                    revealedCount = i
                }
            }
        }
        .accessibilityLabel("\(artwork.name), \(completed ? "complete" : "waiting to be colored")")
    }

    private func drawingPath(_ shape: ArtShape) -> Path {
        switch shape {
        case .polygon(let points):
            return Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
        case let .ellipse(cx, cy, rx, ry):
            return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        case let .rect(x, y, w, h, radius):
            return Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius)
        }
    }
}
