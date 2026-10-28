import SwiftUI

struct LevelSelectView: View {
    @EnvironmentObject private var app: AppModel
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { app.show(.menu) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .heavy))
                }
                .buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
                Spacer()
                Text("Levels")
                    .roundedFont(28, .black)
                    .foregroundColor(Palette.ink)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(app.library.levels) { level in
                        LevelCard(level: level)
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct LevelCard: View {
    @EnvironmentObject private var app: AppModel
    let level: LevelDefinition

    var body: some View {
        let unlocked = app.save.isUnlocked(level.id)
        let stars = app.progress.bestStars[level.id] ?? 0
        Button { app.openLevel(level.id) } label: {
            VStack(spacing: 8) {
                ArtworkThumbnail(artwork: level.artwork, completed: stars > 0)
                    .overlay {
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(Palette.ink)
                                .padding(12).background(Circle().fill(Palette.cream.opacity(0.9)))
                        }
                    }
                Text("Level \(level.id)").roundedFont(12, .heavy).foregroundColor(Palette.wood)
                Text(level.name)
                    .roundedFont(15, .heavy)
                    .foregroundColor(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                StarRow(earned: stars, size: 16)
                Text(stars > 0 ? "Best \(app.progress.bestScores[level.id] ?? 0)" : "\(level.totalPencilsNeeded) pencils")
                    .roundedFont(12, .semibold)
                    .foregroundColor(Palette.ink.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.wood.opacity(0.4), lineWidth: 2))
            .opacity(unlocked ? 1 : 0.65)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked
            ? "Level \(level.id), \(level.name), \(stars) of 3 stars, \(level.totalPencilsNeeded) pencils"
            : "Level \(level.id), locked")
        .accessibilityAddTraits(.isButton)
    }
}

/// A permanent collection derived from the same saved wins as the level list.
struct GalleryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var selectedPicture: LevelDefinition?
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { app.show(.menu) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .heavy))
                }
                .buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
                .accessibilityLabel("Back to menu")
                Spacer()
                Text("Gallery")
                    .roundedFont(28, .black)
                    .foregroundColor(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 16) {
                    Text("\(app.completedLevels.count) of \(app.library.levels.count) pictures coloured")
                        .roundedFont(16, .heavy).foregroundColor(Palette.ink)
                    if app.completedLevels.isEmpty {
                        Text("Finish a level to bring its picture to life here.")
                            .roundedFont(15, .semibold)
                            .foregroundColor(Palette.ink.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(app.library.levels) { level in
                            let completed = app.completedLevels.contains { $0.id == level.id }
                            Button { selectedPicture = level } label: {
                                VStack(spacing: 8) {
                                    ArtworkThumbnail(artwork: level.artwork, completed: completed)
                                    Text(level.artwork.name)
                                        .roundedFont(15, .heavy).foregroundColor(Palette.ink)
                                        .multilineTextAlignment(.center)
                                    if completed {
                                        StarRow(earned: app.progress.bestStars[level.id] ?? 0, size: 16)
                                    } else {
                                        Text("Finish level \(level.id)")
                                            .roundedFont(12, .semibold)
                                            .foregroundColor(Palette.ink.opacity(0.6))
                                    }
                                }
                                .padding(12).frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 20).fill(Palette.panel))
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.wood.opacity(0.3), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .disabled(!completed)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(completed
                                ? "\(level.artwork.name), collected, \(app.progress.bestStars[level.id] ?? 0) of 3 stars. View picture"
                                : "\(level.artwork.name), not collected. Finish level \(level.id)")
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .padding(20)
            }
        }
        .sheet(item: $selectedPicture) { level in
            GalleryPictureView(level: level)
        }
    }
}

private struct GalleryPictureView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let level: LevelDefinition

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
                }
                Text(level.artwork.name).roundedFont(30, .black)
                    .foregroundColor(Palette.ink).multilineTextAlignment(.center)
                ArtworkThumbnail(artwork: level.artwork, completed: true)
                    .frame(maxWidth: 500)
                StarRow(earned: app.progress.bestStars[level.id] ?? 0, size: 30)
                Text("Level \(level.id) · Best \(app.progress.bestScores[level.id] ?? 0)")
                    .roundedFont(16, .bold).foregroundColor(Palette.ink.opacity(0.7))
                Button("Play Again") {
                    dismiss()
                    app.openLevel(level.id)
                }
                    .buttonStyle(ChunkyButtonStyle(color: Palette.green))
                    .frame(maxWidth: 320)
            }
            .padding(24)
        }
        .background(Palette.cream.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
