import Foundation

// All possible application states. The state machine transitions are enforced in App.swift.
enum AppStateValue: Equatable {
    case needsModel       // no model file found on disk
    case idle             // ready, waiting for hotkey
    case recording        // mic is active, accumulating audio
    case transcribing     // whisper-cli subprocess running
    case error(String)    // recoverable error with a human-readable message

    var displayName: String {
        switch self {
        case .needsModel:          return "No model — see menu"
        case .idle:                return "Idle  ·  press ⌘⌥D to start"
        case .recording:           return "Recording — press ⌘⌥D to stop"
        case .transcribing:        return "Transcribing…"
        case .error(let msg):      return "Error: \(msg)"
        }
    }
}

// Thread-safe state holder. Observers are called on the main thread.
final class AppState {
    private var _state: AppStateValue = .idle
    private var observers: [(AppStateValue) -> Void] = []
    private let queue = DispatchQueue(label: "com.whisperdictate.app.state")

    var current: AppStateValue {
        queue.sync { _state }
    }

    func set(_ newState: AppStateValue) {
        queue.async { [weak self] in
            guard let self else { return }
            self._state = newState
            let snapshot = self.observers
            DispatchQueue.main.async {
                snapshot.forEach { $0(newState) }
            }
        }
    }

    // Returns the token needed to remove the observer later (index into array).
    func observe(_ handler: @escaping (AppStateValue) -> Void) {
        queue.async { [weak self] in
            self?.observers.append(handler)
        }
    }
}
