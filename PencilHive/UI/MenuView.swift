import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showSettings = false
    @State private var showHelp = false

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            LogoMark(size: 104).accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("Pencil Hive")
                    .roundedFont(42, .black)
                    .foregroundColor(Palette.ink)
                Text("Sort the tiles. Colour the picture.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .roundedFont(16, .semibold)
                    .foregroundColor(Palette.ink.opacity(0.7))
            }
            if app.loadError == nil {
                Text("\(app.completedLevels.count) of \(app.library.levels.count) pictures coloured")
                    .roundedFont(14, .heavy)
                    .foregroundColor(Palette.ink.opacity(0.6))
            }
            Spacer(minLength: 20)

            if let error = app.loadError {
                Text("Could not load levels.\n\(error)")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Palette.coral)
                    .padding()
            } else {
                VStack(spacing: 14) {
                    Button(action: play) {
                        Text(app.hasSavedGame ? "Continue" : "Play")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Palette.green))

                    Button("Levels") { app.show(.levels) }
                        .buttonStyle(ChunkyButtonStyle(color: Palette.blue))

                    Button("Gallery") { app.show(.gallery) }
                        .buttonStyle(ChunkyButtonStyle(color: TileColor.rose.swiftUIColor))

                    HStack(spacing: 14) {
                        Button("How to Play") { showHelp = true }
                            .buttonStyle(ChunkyButtonStyle(color: TileColor.violet.swiftUIColor, compact: true))
                        Button("Settings") { showSettings = true }
                            .buttonStyle(ChunkyButtonStyle(color: Palette.wood, compact: true))
                    }
                }
                .frame(maxWidth: 320)
            }
            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: geometry.size.height)
        .padding(.horizontal, 28)
        }
        .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHelp) { HowToPlayView() }
    }

    private func play() {
        if let id = app.continueLevelID { app.openLevel(id) }
    }
}
