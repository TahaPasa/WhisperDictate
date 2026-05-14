import Foundation

// The language hint passed to whisper-cli via the -l flag.
// Using the correct language improves accuracy significantly vs. letting the model guess.
enum WhisperLanguage: String, CaseIterable {
    case english = "en"
    case turkish = "tr"
    case german  = "de"
    case auto    = "auto"

    var displayName: String {
        switch self {
        case .english: return "🇬🇧  English"
        case .turkish: return "🇹🇷  Turkish"
        case .german:  return "🇩🇪  German"
        case .auto:    return "🌐  Auto (other)"
        }
    }

    // Persisted across launches in UserDefaults.
    static var current: WhisperLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: "whisperLanguage") ?? "auto"
            return WhisperLanguage(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "whisperLanguage")
            AppLogger.log("Language set to \(newValue.displayName)")
        }
    }
}
