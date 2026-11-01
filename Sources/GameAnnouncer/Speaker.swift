import AVFoundation

/// Speaks announcements one after another using the system voices.
@MainActor
final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()

    var voiceIdentifier: String? = UserDefaults.standard.string(forKey: "voice") {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "voice") }
    }

    static var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance) // queued behind anything already speaking
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
