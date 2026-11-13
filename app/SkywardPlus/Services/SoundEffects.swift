import AVFoundation
import Foundation

/// The app's few sounds, synthesized for Skyward Plus (Resources/Sounds):
/// chimes for new grades and a soft tick for finishing work.
@MainActor
enum SoundEffects {
    enum Effect: String {
        case gradeGreat = "chime-good"
        case grade = "chime"
        case gradeLow = "chime-low"
        case tick
    }

    private static var players: [Effect: AVAudioPlayer] = [:]
    private static var sessionReady = false

    static func play(_ effect: Effect, settings: AppSettings) {
        guard Notifier.isEnabled, settings.soundsOn else { return }
        switch effect {
        case .tick: guard settings.soundTaskTicks else { return }
        default: guard settings.soundGradeChimes else { return }
        }
        #if os(iOS)
        if !sessionReady {
            // Ambient: mixes with music and respects the silent switch.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            sessionReady = true
        }
        #endif
        let player: AVAudioPlayer
        if let cached = players[effect] {
            player = cached
        } else {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
                  let made = try? AVAudioPlayer(contentsOf: url) else { return }
            made.volume = effect == .tick ? 0.5 : 0.7
            made.prepareToPlay()
            players[effect] = made
            player = made
        }
        player.currentTime = 0
        player.play()
    }

    /// The chime that suits a batch of new grades.
    static func effect(forScores scores: [Double]) -> Effect {
        if scores.contains(where: { $0 < 70 }) { return .gradeLow }
        if scores.contains(where: { $0 >= 90 }) { return .gradeGreat }
        return .grade
    }
}
