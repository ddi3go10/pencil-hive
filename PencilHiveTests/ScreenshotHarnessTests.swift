import Foundation
import Testing

#if !canImport(PencilHiveCore)
import SpriteKit
import SwiftUI
import UIKit
@testable import PencilHive

/// Renders the real SwiftUI + SpriteKit screens at phone sizes and writes PNGs for visual review.
/// A no-op unless the output folder below exists, so normal test runs are unaffected.
@Suite("Screenshot harness")
@MainActor
struct ScreenshotHarnessTests {
    private static let outputFolder = "/private/tmp/pencil-hive-shots"

    private struct Phone {
        let name: String
        let size: CGSize
        let safeTop: CGFloat
        let safeBottom: CGFloat
    }

    private static let phones = [
        Phone(name: "compact-390x844", size: CGSize(width: 390, height: 844), safeTop: 47, safeBottom: 34),
        Phone(name: "promax-440x956", size: CGSize(width: 440, height: 956), safeTop: 62, safeBottom: 34),
    ]

    @Test func rendersSettingsOnASmallPhoneAtLargeTextSize() throws {
        guard FileManager.default.fileExists(atPath: Self.outputFolder) else { return }
        let phone = Phone(name: "small-375x667", size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0)
        let app = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
        try render(SettingsView().environmentObject(app).environment(\.dynamicTypeSize, .accessibility2),
                   phone: phone, file: "settings-large-text")
        try render(SettingsView().environmentObject(app).environment(\.dynamicTypeSize, .accessibility2),
                   phone: phone, file: "settings-large-text-scrolled", scrollToBottom: true)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func render(_ app: AppModel, phone: Phone, file: String) throws {
        try render(AnyView(RootView().environmentObject(app)), phone: phone, file: file)
    }

    private func render<V: View>(_ view: V, phone: Phone, file: String, scrollToBottom: Bool = false) throws {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: phone.size))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene = scene }
        window.frame = CGRect(origin: .zero, size: phone.size)
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        // The test window sits in a real simulator scene, so top up (or trim) its own safe area to the phone's.
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: phone.safeTop - window.safeAreaInsets.top + host.additionalSafeAreaInsets.top, left: 0,
            bottom: phone.safeBottom - window.safeAreaInsets.bottom + host.additionalSafeAreaInsets.bottom, right: 0)
        window.layoutIfNeeded()
        spin(1.0)
        if scrollToBottom {
            func firstScrollView(in view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView { return scroll }
                return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
            }
            let scroll = try #require(firstScrollView(in: host.view))
            #expect(scroll.contentSize.height > scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom), animated: false)
            spin(0.1)
        }
        let renderer = UIGraphicsImageRenderer(size: phone.size)
        let image = renderer.image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: phone.size), afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(Self.outputFolder)/\(phone.name)-\(file).png"))
        window.isHidden = true
    }

    @Test func rendersAGameInProgressOnBothPhones() throws {
        guard FileManager.default.fileExists(atPath: Self.outputFolder) else { return }
        for phone in Self.phones {
            let app = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
            let level = try #require(app.library.first)
            let model = GameViewModel(level: level, app: app)
            let screen = ZStack { Palette.cream.ignoresSafeArea(); GameScreen(model: model) }
            // Lay the scene out first so the drag below uses real coordinates.
            model.scene.size = phone.size
            model.scene.insets = SceneInsets(top: 122, bottom: 92)
            model.scene.rebuild()
            for _ in 0..<2 {
                guard let cell = model.scene.engine.legalCells.first else { break }
                let center = model.scene.layout.center(of: cell)
                model.scene.pointerDown(at: model.scene.slotCenters[0])
                model.scene.pointerMoved(to: CGPoint(x: center.x, y: center.y - model.scene.dragLift))
                try render(screen, phone: phone, file: "drag\(model.scene.engine.state.movesUsed)")
                model.scene.pointerUp(at: CGPoint(x: center.x, y: center.y - model.scene.dragLift))
                spin(1.5)
            }
            try render(screen, phone: phone, file: "ingame")
        }
    }

    @Test func rendersMenuAndEveryLevelOnBothPhones() throws {
        guard FileManager.default.fileExists(atPath: Self.outputFolder) else { return }
        for phone in Self.phones {
            let app = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
            try render(app, phone: phone, file: "menu")
            app.show(.levels)
            try render(app, phone: phone, file: "levels")
            for level in app.library.levels {
                let fresh = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
                fresh.show(.game(level.id))
                try render(fresh, phone: phone, file: "level\(level.id)")
            }
        }
    }

    @Test func rendersRewardAndGalleryAtSmallAndLargeTextSizes() throws {
        guard FileManager.default.fileExists(atPath: Self.outputFolder) else { return }
        let compact = Phone(name: "small-375x667", size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0)
        for phone in [compact] + Self.phones {
            let app = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
            app.show(.gallery)
            try render(app, phone: phone, file: "gallery-empty")
            let level = try #require(app.library.first)
            var engine = GameEngine(level: level)
            let moves = try #require(Solver(level: level).solve().moves)
            for move in moves {
                engine.place(slot: try #require(engine.state.tray.firstIndex { $0 == move.stack }), at: move.cell)
            }
            let model = GameViewModel(level: level, app: app)
            model.scene.engine = engine
            model.scene.phase = .finished
            model.gameScene(model.scene, engineDidAdvance: engine)
            model.gameScene(model.scene, didUpdate: engine)
            model.gameScene(model.scene, didFinishWith: engine.state.status, engine: engine)
            let screen = ZStack { Palette.cream.ignoresSafeArea(); GameScreen(model: model) }
            try render(screen, phone: phone, file: "reward")
            try render(screen.environment(\.dynamicTypeSize, .accessibility2), phone: phone, file: "reward-large-text")
            app.show(.gallery)
            try render(app, phone: phone, file: "gallery-collected")
            try render(AnyView(RootView().environmentObject(app).environment(\.dynamicTypeSize, .accessibility2)), phone: phone, file: "gallery-large-text")
        }
    }

    @Test func rendersReviewRegressionLayouts() throws {
        guard FileManager.default.fileExists(atPath: Self.outputFolder) else { return }
        let narrow = Phone(name: "narrow-320x568", size: CGSize(width: 320, height: 568), safeTop: 20, safeBottom: 0)
        let small = Phone(name: "small-375x667", size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0)
        let tall = Phone(name: "tall-375x1400", size: CGSize(width: 375, height: 1400), safeTop: 20, safeBottom: 0)

        let galleryApp = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
        galleryApp.show(.gallery)
        try render(AnyView(RootView().environmentObject(galleryApp).environment(\.dynamicTypeSize, .accessibility2)),
                   phone: narrow, file: "gallery-accessibility2")

        let rewardApp = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
        let finalLevel = try #require(rewardApp.library.level(id: 20))
        let rewardModel = GameViewModel(level: finalLevel, app: rewardApp)
        var wonState = rewardModel.scene.engine.state
        wonState.status = .won(stars: 3)
        wonState.score = 2_000
        wonState.filledRegions = finalLevel.artwork.regions.map(\.id)
        let wonEngine = GameEngine(level: finalLevel, state: wonState)
        rewardModel.scene.engine = wonEngine
        rewardModel.scene.phase = .finished
        rewardModel.gameScene(rewardModel.scene, didFinishWith: wonEngine.state.status, engine: wonEngine)
        let rewardScreen = GameScreen(model: rewardModel).environment(\.dynamicTypeSize, .accessibility2)
        try render(rewardScreen, phone: small, file: "reward-accessibility2")
        try render(rewardScreen, phone: tall, file: "reward-accessibility2-full-content")

        let scoreApp = AppModel(save: SaveStore(storage: InMemorySaveStorage()), bundle: .main)
        let level = try #require(scoreApp.library.level(id: 3))
        let scoreModel = GameViewModel(level: level, app: scoreApp)
        let route: [(Int, Int, Int)] = [
            (0, 0, -1), (1, -1, 1), (2, 0, 0), (2, 0, 1), (1, -1, 2), (0, -1, 1),
            (0, 0, 0), (1, 1, 0), (2, -2, 2), (0, -1, 0), (2, 0, 0), (1, 0, -1),
        ]
        var engine = GameEngine(level: level)
        for (slot, q, r) in route {
            engine.place(slot: slot, at: HexCoord(q: q, r: r))
        }
        scoreModel.gameScene(scoreModel.scene, didUpdate: engine)
        try render(GameScreen(model: scoreModel).environment(\.dynamicTypeSize, .xLarge),
                   phone: small, file: "reachable-score-1205")
        try render(GameScreen(model: scoreModel).environment(\.dynamicTypeSize, .xLarge),
                   phone: narrow, file: "reachable-score-1205")
    }
}
#endif
