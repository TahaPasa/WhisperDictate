import Foundation

// Runs whisper-cli as a subprocess and returns the transcribed text.
// whisper-cli flags used:
//   -m  model path
//   -f  input WAV
//   -l  auto   → auto-detect language
//   -nt         → no timestamps in output
//   -np         → no progress/prints, only the result on stdout
//   -t  N       → use all available CPU threads
final class Transcriber {
    private let modelManager: ModelManager
    // Resolved once at init: Bundle.main lookups on every transcription are
    // pointless work and the path cannot change at runtime.
    private let binaryURL: URL
    // Hard ceiling for a single whisper-cli invocation. Generous enough for the
    // large-v3-turbo (~1.5 GB) on CPU + a 60s recording, but bounded so the app
    // never hangs forever on a stalled subprocess.
    private let transcriptionTimeout: TimeInterval = 180

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
        self.binaryURL = Self.resolveWhisperCLIURL()
    }

    func transcribe(wav: URL) async throws -> String {
        defer { try? FileManager.default.removeItem(at: wav) }

        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw TranscriberError.binaryMissing(binaryURL.path)
        }
        guard let modelURL = modelManager.activeModelURL else {
            throw TranscriberError.modelMissing
        }

        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        let language = WhisperLanguage.current
        let args: [String] = [
            "-m", modelURL.path,
            "-f", wav.path,
            "-l", language.rawValue,   // user-selected: tr / de / auto
            "-nt",                     // no timestamps
            "-np",                     // suppress all prints except result
            "-t", "\(threads)",
        ]

        AppLogger.log("Running: \(binaryURL.lastPathComponent) \(args.joined(separator: " "))")

        let timeout = transcriptionTimeout
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = args

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError  = stderr

            // Guard against a stalled subprocess: if it doesn't exit within `timeout`,
            // terminate it and resume with a clear error. The flag is wrapped in a
            // reference type so both closures share the same storage safely.
            let flag = TimeoutFlag()
            let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
            timeoutTimer.schedule(deadline: .now() + timeout)
            timeoutTimer.setEventHandler {
                guard process.isRunning else { return }
                flag.set()
                AppLogger.log("Transcription exceeded \(Int(timeout))s — terminating", level: .warn)
                process.terminate()
            }

            process.terminationHandler = { p in
                timeoutTimer.cancel()
                let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if !err.isEmpty {
                    AppLogger.log("whisper-cli stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))", level: .warn)
                }
                if flag.isSet {
                    continuation.resume(throwing: TranscriberError.timedOut(Int(timeout)))
                    return
                }
                if p.terminationStatus != 0 {
                    // Distinguish the common failure modes by inspecting stderr.
                    let errLower = err.lowercased()
                    if errLower.contains("model") || errLower.contains("ggml") {
                        continuation.resume(throwing: TranscriberError.modelInvalid)
                    } else if errLower.contains("wav") || errLower.contains("audio") {
                        continuation.resume(throwing: TranscriberError.audioInvalid)
                    } else {
                        continuation.resume(throwing: TranscriberError.nonZeroExit(Int(p.terminationStatus)))
                    }
                } else {
                    continuation.resume(returning: out.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            do {
                try process.run()
                timeoutTimer.resume()
            } catch {
                timeoutTimer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    // Resolves whisper-cli path: bundled Resources/bin/ first, then the repo build path for dev runs.
    private static func resolveWhisperCLIURL() -> URL {
        // In a .app bundle: Contents/Resources/bin/whisper-cli
        if let bundlePath = Bundle.main.url(forResource: "whisper-cli", withExtension: nil,
                                             subdirectory: "bin") {
            return bundlePath
        }
        // Fallback for running `swift run` from the repo root during development
        let repoPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Sources/WhisperDictate/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // WhisperDictate/
            .appendingPathComponent("whisper.cpp/build/bin/whisper-cli")
        return repoPath
    }
}

// Reference-typed flag so the timeout closure and termination closure can
// safely share state under Swift's strict concurrency rules.
private final class TimeoutFlag {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

enum TranscriberError: Error, LocalizedError {
    case binaryMissing(String)
    case modelMissing
    case modelInvalid
    case audioInvalid
    case timedOut(Int)
    case nonZeroExit(Int)

    var errorDescription: String? {
        switch self {
        case .binaryMissing(let p): return "whisper-cli not found at \(p)"
        case .modelMissing:         return "No model file found. Download one from the menu."
        case .modelInvalid:         return "Selected model file appears to be invalid or corrupted"
        case .audioInvalid:         return "Audio recording was unreadable (try recording again)"
        case .timedOut(let s):      return "Transcription took longer than \(s) seconds and was cancelled"
        case .nonZeroExit(let c):   return "whisper-cli exited with code \(c)"
        }
    }
}
