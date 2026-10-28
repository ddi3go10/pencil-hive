import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Sound cues. Every sound is synthesised in code, so there are no audio assets.
enum SoundCue: CaseIterable {
    case pickup, place, merge, pencil, paint, win, fail, boost, error
}

enum HapticKind {
    case light, medium, heavy, success, warning
}

/// Plays optional sounds and haptics. Both can be switched off in Settings.
final class Feedback {
    var soundEnabled: Bool
    var hapticsEnabled: Bool
    private var players: [SoundCue: [AVAudioPlayer]] = [:]
    private var nextIndex: [SoundCue: Int] = [:]
    private let playersLock = NSLock()
    private static let voicesPerCue = 3

    #if canImport(UIKit) && !os(tvOS)
    private lazy var lightImpact = UIImpactFeedbackGenerator(style: .light)
    private lazy var mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private lazy var heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var notificationGenerator = UINotificationFeedbackGenerator()
    #endif

    init(soundEnabled: Bool = true, hapticsEnabled: Bool = true) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        #if os(iOS)
        // Activating the audio session can block for seconds on a cold start, so keep it off the
        // main thread. Ambient mixes with the player's music and respects the silent switch.
        // The players are also built here: creating or preparing one activates the session implicitly,
        // which iOS warns about when it happens on the main thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            var built: [SoundCue: [AVAudioPlayer]] = [:]
            for cue in SoundCue.allCases {
                let data = SoundSynth.wav(for: cue)
                var pool: [AVAudioPlayer] = []
                for _ in 0..<Self.voicesPerCue {
                    if let player = try? AVAudioPlayer(data: data) {
                        player.prepareToPlay()
                        pool.append(player)
                    }
                }
                if !pool.isEmpty { built[cue] = pool }
            }
            self?.install(built)
        }
        #endif
    }

    private func install(_ built: [SoundCue: [AVAudioPlayer]]) {
        playersLock.lock()
        players = built
        playersLock.unlock()
    }

    func play(_ cue: SoundCue) {
        guard soundEnabled else { return }
        playersLock.lock()
        guard let pool = players[cue], !pool.isEmpty else {
            playersLock.unlock()
            return
        }
        let cursor = nextIndex[cue, default: 0]
        let chosen: AVAudioPlayer
        if let idle = pool.first(where: { !$0.isPlaying }) {
            chosen = idle
        } else {
            chosen = pool[cursor % pool.count]
            nextIndex[cue] = (cursor + 1) % pool.count
        }
        playersLock.unlock()
        // A cue requested before the players finish loading (the first moments after launch) stays silent.
        chosen.currentTime = 0
        chosen.play()
    }

    func haptic(_ kind: HapticKind) {
        guard hapticsEnabled else { return }
        #if canImport(UIKit) && !os(tvOS)
        switch kind {
        case .light:
            lightImpact.impactOccurred()
            lightImpact.prepare()
        case .medium:
            mediumImpact.impactOccurred()
            mediumImpact.prepare()
        case .heavy:
            heavyImpact.impactOccurred()
            heavyImpact.prepare()
        case .success:
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        }
        #endif
    }
}

/// Builds tiny 16-bit mono WAV files from sine tones with a quick fade, one per cue.
enum SoundSynth {
    private static let sampleRate = 22_050.0

    private struct Note {
        let frequency: Double
        let duration: Double
        var delay: Double = 0
        var volume: Double = 0.5
        /// Pitch glide target (Hz) reached at the end of the note, or nil for a steady tone.
        var glideTo: Double?
    }

    static func wav(for cue: SoundCue) -> Data {
        let notes: [Note]
        switch cue {
        case .pickup: notes = [Note(frequency: 520, duration: 0.07, volume: 0.35)]
        case .place: notes = [Note(frequency: 180, duration: 0.12, volume: 0.6, glideTo: 110)]
        case .merge: notes = [Note(frequency: 440, duration: 0.09, volume: 0.4, glideTo: 620)]
        case .pencil: notes = [
            Note(frequency: 660, duration: 0.09), Note(frequency: 880, duration: 0.09, delay: 0.07),
            Note(frequency: 1320, duration: 0.16, delay: 0.14),
        ]
        case .paint: notes = [Note(frequency: 990, duration: 0.07, volume: 0.35), Note(frequency: 1480, duration: 0.14, delay: 0.05, volume: 0.35)]
        case .win: notes = [
            Note(frequency: 523, duration: 0.14), Note(frequency: 659, duration: 0.14, delay: 0.12),
            Note(frequency: 784, duration: 0.14, delay: 0.24), Note(frequency: 1047, duration: 0.35, delay: 0.36),
        ]
        case .fail: notes = [Note(frequency: 330, duration: 0.18), Note(frequency: 262, duration: 0.18, delay: 0.16), Note(frequency: 196, duration: 0.3, delay: 0.32)]
        case .boost: notes = [Note(frequency: 400, duration: 0.18, volume: 0.4, glideTo: 900)]
        case .error: notes = [Note(frequency: 150, duration: 0.12, volume: 0.45)]
        }

        let total = (notes.map { $0.delay + $0.duration }.max() ?? 0.1) + 0.02
        var samples = [Double](repeating: 0, count: Int(total * sampleRate))
        for note in notes {
            let start = Int(note.delay * sampleRate)
            let count = Int(note.duration * sampleRate)
            var phase = 0.0
            for i in 0..<count where start + i < samples.count {
                let t = Double(i) / Double(count)
                let frequency = note.frequency + (note.glideTo.map { $0 - note.frequency } ?? 0) * t
                phase += 2 * Double.pi * frequency / sampleRate
                let envelope = min(1, t * 20) * pow(1 - t, 1.6)
                samples[start + i] += sin(phase) * envelope * note.volume
            }
        }
        return encode(samples)
    }

    private static func encode(_ samples: [Double]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * Double(Int16.max))
            pcm.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Array($0) })
        }
        func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        func le16(_ v: UInt16) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8)); header.append(contentsOf: le32(UInt32(36 + pcm.count)))
        header.append(contentsOf: Array("WAVEfmt ".utf8)); header.append(contentsOf: le32(16))
        header.append(contentsOf: le16(1)); header.append(contentsOf: le16(1))
        header.append(contentsOf: le32(UInt32(sampleRate))); header.append(contentsOf: le32(UInt32(sampleRate) * 2))
        header.append(contentsOf: le16(2)); header.append(contentsOf: le16(16))
        header.append(contentsOf: Array("data".utf8)); header.append(contentsOf: le32(UInt32(pcm.count)))
        return header + pcm
    }
}
