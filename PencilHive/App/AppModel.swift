import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// App-wide state: which screen is showing, the level library, saved progress and settings.
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case menu
        case levels
        case gallery
        case game(Int)
    }

    @Published var screen: Screen = .menu
    @Published private(set) var progress: PlayerProgress
    @Published private(set) var settings: GameSettings
    @Published private(set) var hasSavedGame: Bool

    let library: LevelLibrary
    let loadError: String?
    let save: SaveStore
    let feedback: Feedback

    /// Only finished pictures from the current catalog belong in the collection.
    var completedLevels: [LevelDefinition] {
        library.levels.filter { (progress.bestStars[$0.id] ?? 0) > 0 }
    }

    init(save: SaveStore = SaveStore(storage: FileSaveStorage.standard), bundle: Bundle = .main) {
        self.save = save
        var loaded: LevelLibrary
        var error: String?
        do {
            loaded = try LevelLibrary.bundled(in: bundle)
        } catch let caught {
            loaded = LevelLibrary(levels: [])
            error = String(describing: caught)
        }
        library = loaded
        loadError = error
        progress = save.progress
        settings = save.settings
        hasSavedGame = save.data.inProgress != nil
        feedback = Feedback(soundEnabled: save.settings.soundEnabled, hapticsEnabled: save.settings.hapticsEnabled)
    }

    // MARK: Navigation

    func show(_ screen: Screen) {
        if Self.reduceMotion {
            self.screen = screen
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { self.screen = screen }
        }
        refresh()
    }

    private static var reduceMotion: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }

    func openLevel(_ id: Int) {
        guard library.level(id: id) != nil, save.isUnlocked(id) else { return }
        show(.game(id))
    }

    /// Level the "Play" button opens: the saved game, otherwise the furthest unlocked level.
    var continueLevelID: Int? {
        if let saved = save.data.inProgress, library.level(id: saved.levelID) != nil { return saved.levelID }
        let unlocked = library.levels.last { save.isUnlocked($0.id) }
        return unlocked?.id ?? library.first?.id
    }

    func makeViewModel(for levelID: Int) -> GameViewModel? {
        guard let level = library.level(id: levelID) else { return nil }
        return GameViewModel(level: level, app: self)
    }

    // MARK: Settings and progress

    func setSound(_ enabled: Bool) {
        save.updateSettings { $0.soundEnabled = enabled }
        feedback.soundEnabled = enabled
        refresh()
    }

    func setHaptics(_ enabled: Bool) {
        save.updateSettings { $0.hapticsEnabled = enabled }
        feedback.hapticsEnabled = enabled
        refresh()
    }

    func setTileSymbols(_ enabled: Bool) {
        save.updateSettings { $0.tileSymbols = enabled }
        refresh()
    }

    /// Tile shapes show when the player turned them on or the system asks to differentiate without colour.
    var showsTileSymbols: Bool {
        #if canImport(UIKit)
        return settings.tileSymbols || UIAccessibility.shouldDifferentiateWithoutColor
        #else
        return settings.tileSymbols
        #endif
    }

    func resetProgress() {
        save.resetAll()
        refresh()
    }

    func refresh() {
        progress = save.progress
        settings = save.settings
        hasSavedGame = save.data.inProgress != nil
    }
}
