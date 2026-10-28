import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.cream
                    .ignoresSafeArea()
                switch app.screen {
                case .menu:
                    MenuView().transition(.opacity)
                case .levels:
                    LevelSelectView().transition(reduceMotion ? .opacity : .move(edge: .trailing))
                case .gallery:
                    GalleryView().transition(reduceMotion ? .opacity : .move(edge: .trailing))
                case .game(let id):
                    GameHost(levelID: id).id(id).transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Palette.cream.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Creates the game's view model once per level, then shows the game screen.
private struct GameHost: View {
    @EnvironmentObject private var app: AppModel
    let levelID: Int
    @State private var model: GameViewModel?

    var body: some View {
        Group {
            if let model {
                GameScreen(model: model)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = app.makeViewModel(for: levelID) }
        }
    }
}
