import SpriteKit
import SwiftUI

struct GameScreen: View {
    @ObservedObject var model: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.scenePhase) private var scenePhase

    /// Space the HUD and booster bar take, reserved so the SpriteKit scene lays itself out around them.
    private let hudHeight: CGFloat = 100
    private let boosterBarHeight: CGFloat = 84

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: model.scene, options: [.ignoresSiblingOrder])
                    .frame(width: geo.size.width, height: geo.size.height)

                VStack(spacing: 0) {
                    // The HUD and booster bar have a fixed height the scene lays itself out around, so
                    // their text stops growing at "xLarge"; VoiceOver reads every value in full.
                    HUDView(model: model)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .frame(height: hudHeight)
                    Spacer(minLength: 0)
                    BoosterBar(model: model)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .frame(height: boosterBarHeight)
                }

                if model.hammerActive {
                    Text("Tap a stack to smash it")
                        .roundedFont(16, .heavy)
                        .foregroundColor(Palette.coral)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Palette.panel))
                        .position(x: geo.size.width / 2, y: geo.size.height - boosterBarHeight - 18)
                        .allowsHitTesting(false)
                }

                if let overlay = model.overlay {
                    OverlayView(model: model, overlay: overlay)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .alert("Restart this level?", isPresented: $model.restartConfirmation) {
                Button("Keep Playing", role: .cancel) {}
                Button("Restart", role: .destructive) { model.restart() }
            } message: {
                Text("Your current board will be reset. Completed levels and best scores will be kept.")
            }
            .onAppear {
                applyInsets(geo)
                model.updateAccessibilitySettings(differentiateWithoutColor: differentiateWithoutColor)
            }
            .onChange(of: differentiateWithoutColor) { enabled in
                model.updateAccessibilitySettings(differentiateWithoutColor: enabled)
            }
            .onChange(of: reduceMotion) { _ in
                model.scene.updateHammerHighlights()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    model.updateAccessibilitySettings(differentiateWithoutColor: differentiateWithoutColor)
                }
            }
            .onChange(of: geo.safeAreaInsets.top) { _ in applyInsets(geo) }
            .onChange(of: geo.safeAreaInsets.bottom) { _ in applyInsets(geo) }
            .onChange(of: geo.size) { _ in applyInsets(geo) }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: model.overlay)
        }
    }

    private func applyInsets(_ geo: GeometryProxy) {
        model.updateInsets(top: hudHeight, bottom: boosterBarHeight)
    }
}

// MARK: HUD

struct HUDView: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.pause() } label: {
                    Image(systemName: "pause.fill").font(.system(size: 16, weight: .heavy))
                }
                .buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
                .accessibilityLabel("Pause")

                PencilProgressView(done: model.hud.pencilsDone, total: model.hud.pencilsTotal, colors: model.hud.pencilColors)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .accessibilityLabel("\(model.hud.pencilsDone) of \(model.hud.pencilsTotal) pencils done")
                Button { model.requestRestart() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .heavy))
                }
                .buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
                .accessibilityLabel("Restart level")
                .disabled(!model.canRequestRestart)
                Pill(icon: "star.fill", text: "\(model.hud.score)", tint: TileColor.amber.swiftUIColor)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Score \(model.hud.score)")
            }

            HStack(spacing: 6) {
                if let moves = model.hud.movesRemaining {
                    Pill(icon: "arrow.right.circle.fill", text: "\(moves)", tint: moves <= 3 ? Palette.coral : Palette.ink)
                        .accessibilityLabel("\(moves) moves left")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.hud.goals) { chip in
                            GoalChipView(chip: chip, showsSymbol: model.showsSymbols)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pencils still needed by color")
                .accessibilityValue(model.hud.goals.map { chip in
                    chip.remaining == 0 ? "\(chip.color.displayName) complete"
                        : "\(chip.remaining) \(chip.color.displayName) pencils needed"
                }.joined(separator: ". "))
            }
            if model.showsPlacementHint {
                Text("Drag a stack onto an empty hex")
                    .roundedFont(11, .bold)
                    .foregroundColor(Palette.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

private struct GoalChipView: View {
    let chip: HUDSnapshot.GoalChip
    let showsSymbol: Bool

    var body: some View {
        HStack(spacing: 2) {
            ZStack {
                HexagonShape().fill(chip.color.swiftUIColor).frame(width: 16, height: 14)
                if showsSymbol && chip.remaining > 0 {
                    SymbolShape(symbol: chip.color.symbol)
                        .fill(chip.color.prefersDarkSymbol ? Palette.ink : Color.white, style: FillStyle(eoFill: chip.color.symbol.usesEvenOddFill))
                        .frame(width: 8, height: 8)
                }
                if chip.remaining == 0 {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundColor(.white)
                }
            }
            Text("\(chip.remaining)")
                .roundedFont(13, .heavy)
                .foregroundColor(Palette.ink)
                .monospacedDigit()
        }
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.panel.opacity(0.92)))
        .overlay(Capsule().strokeBorder(Palette.wood.opacity(0.3), lineWidth: 1.2))
        .opacity(chip.remaining == 0 ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.remaining == 0
            ? "\(chip.color.displayName) pencils done"
            : "\(chip.color.displayName) pencils left: \(chip.remaining)")
    }
}

// MARK: Boosters

struct BoosterBar: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        HStack(spacing: 30) {
            BoosterButton(icon: "arrow.uturn.backward", title: "Undo", count: model.hud.undo, enabled: model.hud.canUndo, tint: Palette.blue) {
                model.undo()
            }
            BoosterButton(icon: "hammer.fill", title: "Hammer", count: model.hud.hammer, enabled: model.hud.canHammer, tint: Palette.coral, active: model.hammerActive) {
                model.toggleHammer()
            }
            BoosterButton(icon: "arrow.triangle.2.circlepath", title: "Swap", count: model.hud.refresh, enabled: model.hud.canRefresh, tint: TileColor.violet.swiftUIColor) {
                model.refreshTray()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

private struct BoosterButton: View {
    let icon: String
    let title: String
    let count: Int
    let enabled: Bool
    let tint: Color
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 3))
                    .shadow(color: Palette.ink.opacity(0.25), radius: 0, y: 3)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                    )
                    .frame(width: 58, height: 58)
                    .opacity(enabled ? 1 : 0.4)
                Text("\(count)")
                    .roundedFont(12, .black)
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Palette.coral))
                    .overlay(Circle().strokeBorder(Palette.cream, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
            .frame(width: 66, height: 66)
            .overlay(Circle().strokeBorder(active ? Palette.gold : .clear, lineWidth: 3).frame(width: 64, height: 64))
            .padding(.bottom, 6)
        }
        .buttonStyle(BoosterPlaqueStyle())
        .disabled(!enabled)
        .accessibilityLabel("\(title), \(count) left")
    }
}

/// PlainButtonStyle adds platform dimming to the whole label when disabled.
/// Keep that decision local to the plaque/icon so the red count badge stays readable.
private struct BoosterPlaqueStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: Overlays

struct OverlayView: View {
    @ObservedObject var model: GameViewModel
    let overlay: GameOverlay

    var body: some View {
        ZStack {
            (isWin ? Palette.cream : Color.black.opacity(isResult ? 0.3 : 0.45)).ignoresSafeArea()
            VStack(spacing: 0) {
                if isResult && !isWin { Spacer(minLength: 0) }
                // At large text sizes the card can be taller than the screen, so it scrolls then.
                ViewThatFits(in: .vertical) {
                    card
                    ScrollView { card }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .padding(.horizontal, 24)
                .padding(.bottom, isResult && !isWin ? 40 : 0)
                .accessibilityAddTraits(.isModal)
            }
        }
    }

    private var card: some View {
        VStack(spacing: isWin ? 10 : 14) {
            content
        }
        .padding(isWin ? 18 : 22)
        .frame(maxWidth: isWin ? 390 : 330)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.cream))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Palette.wood, lineWidth: 4))
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    /// The win is a dedicated picture reward; failure stays close to the board and Undo.
    private var isWin: Bool {
        if case .won = overlay { return true }
        return false
    }

    private var isResult: Bool {
        if case .pause = overlay { return false }
        return true
    }

    @ViewBuilder
    private var content: some View {
        switch overlay {
        case .pause:
            title("Paused")
            Text("Level \(model.level.id) · \(model.level.name) · \(model.level.pencilSize) tiles = 1 pencil")
                .roundedFont(14, .bold)
                .multilineTextAlignment(.center)
                .foregroundColor(Palette.ink.opacity(0.65))
            StarLinesView(lines: GameViewModel.starLines(for: model.scene.engine), showsResult: false)
            Button("Resume") { model.resume() }.buttonStyle(ChunkyButtonStyle(color: Palette.green))
            Button("Restart") { model.requestRestart() }.buttonStyle(ChunkyButtonStyle(color: Palette.blue))
            Button("Levels") { model.showLevels() }.buttonStyle(ChunkyButtonStyle(color: TileColor.violet.swiftUIColor))
            Button("Main Menu") { model.exitToMenu() }.buttonStyle(ChunkyButtonStyle(color: Palette.wood))

        case let .won(stars, score, best, isNewBest, hasNext, bestChain, lines):
            title("Picture complete!")
            ArtworkThumbnail(artwork: model.level.artwork, completed: true, animateReveal: true)
                .frame(maxWidth: 240)
            Text(model.level.artwork.name)
                .roundedFont(17, .bold)
                .foregroundColor(Palette.ink.opacity(0.7))
            Text("\(model.hud.pencilsDone)/\(model.hud.pencilsTotal) pencils")
                .roundedFont(14, .bold).foregroundColor(Palette.ink)
            StarRow(earned: stars, size: 36)
            StarLinesView(lines: lines, showsResult: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    rewardScoreText(score)
                    rewardScoreDetails(isNewBest: isNewBest, best: best, bestChain: bestChain)
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 2) {
                    rewardScoreText(score)
                    rewardScoreDetails(isNewBest: isNewBest, best: best, bestChain: bestChain)
                }
            }
            if hasNext {
                Button("Next Level") { model.playNext() }.buttonStyle(ChunkyButtonStyle(color: Palette.green))
            } else {
                Text("You finished every level. More pictures are coming!")
                    .roundedFont(14, .semibold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Palette.ink.opacity(0.7))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    rewardReplayButton
                    rewardGalleryButton
                    rewardMenuButton
                }
                VStack(spacing: 8) {
                    rewardReplayButton
                    rewardGalleryButton
                    rewardMenuButton
                }
            }

        case let .failed(reason, canUndo):
            title(reason.headline)
            Text(reason.detail)
                .roundedFont(15, .semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(Palette.ink.opacity(0.75))
            Button("Try Again") { model.restart() }.buttonStyle(ChunkyButtonStyle(color: Palette.green))
            if canUndo {
                Button("Undo Last Move") { model.undo() }.buttonStyle(ChunkyButtonStyle(color: Palette.blue))
            }
            Button("Levels") { model.showLevels() }.buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .roundedFont(isWin ? 26 : 30, .black)
            .foregroundColor(Palette.ink)
            .multilineTextAlignment(.center)
    }

    private func rewardScoreText(_ score: Int) -> some View {
        Text("\(score)")
            .roundedFont(30, .black)
            .foregroundColor(Palette.ink)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func rewardScoreDetails(isNewBest: Bool, best: Int, bestChain: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isNewBest ? "New best!" : "Best \(best)")
                .roundedFont(13, .heavy)
                .foregroundColor(isNewBest ? Palette.coral : Palette.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if bestChain >= 1 {
                Text("Best chain x\(bestChain + 1)")
                    .roundedFont(12, .heavy)
                    .foregroundColor(Palette.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rewardReplayButton: some View {
        Button { model.restart() } label: {
            Text("Replay").lineLimit(1).minimumScaleFactor(0.75)
        }
        .buttonStyle(ChunkyButtonStyle(color: Palette.blue, compact: true))
    }

    private var rewardGalleryButton: some View {
        Button { model.showGallery() } label: {
            Text("Gallery").lineLimit(1).minimumScaleFactor(0.75)
        }
        .buttonStyle(ChunkyButtonStyle(color: TileColor.rose.swiftUIColor, compact: true))
    }

    private var rewardMenuButton: some View {
        Button { model.exitToMenu() } label: {
            Text("Menu").lineLimit(1).minimumScaleFactor(0.75)
        }
        .buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
    }
}

/// The three ways to earn a star. On the pause card they are goals; on the result card they carry
/// a tick or a cross.
struct StarLinesView: View {
    let lines: [StarLine]
    let showsResult: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                HStack(spacing: 8) {
                    Image(systemName: showsResult ? (line.earned ? "star.fill" : "star") : "star")
                        .foregroundColor(showsResult && !line.earned ? Palette.ink.opacity(0.3) : Palette.gold)
                    Text(line.text)
                        .roundedFont(15, .bold)
                        .foregroundColor(Palette.ink.opacity(showsResult && !line.earned ? 0.45 : 0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(showsResult ? "\(line.text), \(line.earned ? "earned" : "missed")" : line.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

extension FailReason {
    var headline: String { AccessibilityText.headline(self) }
    var detail: String { AccessibilityText.detail(self) }
}
