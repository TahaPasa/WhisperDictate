import Foundation
import CryptoKit

// A single ready-to-download model from the upstream whisper.cpp HuggingFace repo.
// Exposed in the Model menu as a "Download X…" entry. The URL is explicit so users
// can audit/verify it via the menu tooltip or by clicking "Show URLs" in the menu.
struct DownloadableModel: Equatable {
    let id: String           // stable identifier, e.g. "base"
    let filename: String     // file written to disk, e.g. "ggml-base.bin"
    let url: URL             // explicit source URL
    let displayName: String  // human label, e.g. "Base (multilingual)"
    let approxSize: String   // human size string, e.g. "~142 MB"
}

// Manages the whisper.cpp GGML model files.
// All models live in a single user-visible directory: ~/Documents/WhisperDictate/Models/
// The user can drop any .bin file there and the app will discover it automatically.
final class ModelManager {
    // The shipped catalog of one-click downloads. All URLs point at the official
    // ggerganov/whisper.cpp HuggingFace repo. Adding a new entry here automatically
    // adds a new menu item — no other code changes required.
    static let catalog: [DownloadableModel] = [
        DownloadableModel(
            id: "base",
            filename: "ggml-base.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            displayName: "Base (multilingual)",
            approxSize: "~142 MB"
        ),
        DownloadableModel(
            id: "base.en",
            filename: "ggml-base.en.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            displayName: "Base English-only",
            approxSize: "~142 MB"
        ),
        DownloadableModel(
            id: "large-v3-turbo",
            filename: "ggml-large-v3-turbo.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
            displayName: "Large v3 Turbo (multilingual)",
            approxSize: "~1.5 GB"
        ),
    ]

    // Optional environment override for any catalog URL, useful for mirrors:
    // setting WHISPER_DICTATE_MODEL_URL replaces the URL of the *base* catalog
    // entry only (the default download). Other entries always use their canonical URL.
    private static func resolvedURL(for model: DownloadableModel) -> URL {
        if model.id == "base",
           let override = ProcessInfo.processInfo.environment["WHISPER_DICTATE_MODEL_URL"],
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        return model.url
    }

    private let defaults = UserDefaults.standard
    private let selectedModelKey = "selectedModelPath"

    // User-visible models directory. Lives under ~/Documents so it shows up in
    // Finder's sidebar — users can drop .bin files into it directly.
    var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperDictate/Models", isDirectory: true)
    }

    // Legacy directory from earlier builds. Used only for one-time migration.
    private var legacyModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperDictate/models", isDirectory: true)
    }

    // Migrates any .bin files from the old App Support location into the new
    // Documents location, then removes the old folder if it ends up empty.
    // Idempotent: safe to call on every launch.
    func migrateLegacyModelsIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyModelsDirectory.path) else { return }
        try? fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        guard let items = try? fm.contentsOfDirectory(at: legacyModelsDirectory,
                                                      includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles) else { return }
        var moved = 0
        for src in items where src.pathExtension == "bin" {
            let dst = modelsDirectory.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) {
                // Already migrated — remove the stale copy
                try? fm.removeItem(at: src)
            } else {
                do { try fm.moveItem(at: src, to: dst); moved += 1 }
                catch { AppLogger.log("Could not migrate \(src.lastPathComponent): \(error)", level: .warn) }
            }
        }
        if moved > 0 {
            AppLogger.log("Migrated \(moved) model(s) from Application Support → Documents/WhisperDictate/Models")
        }

        // If a stored selectedModelPath points at the old location, rewrite it
        if let saved = defaults.string(forKey: selectedModelKey),
           saved.contains("/Application Support/WhisperDictate/models/") {
            let filename = (saved as NSString).lastPathComponent
            let newPath = modelsDirectory.appendingPathComponent(filename).path
            if fm.fileExists(atPath: newPath) {
                defaults.set(newPath, forKey: selectedModelKey)
            } else {
                defaults.removeObject(forKey: selectedModelKey)
            }
        }

        // Try removing the now-empty legacy folder (and its parent WhisperDictate/ if also empty)
        if let leftover = try? fm.contentsOfDirectory(atPath: legacyModelsDirectory.path), leftover.isEmpty {
            try? fm.removeItem(at: legacyModelsDirectory)
        }
    }

    // All .bin files in modelsDirectory, sorted alphabetically.
    var availableModels: [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return items
            .filter { $0.pathExtension == "bin" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // The currently selected model. Falls back to first discovered model, then nil.
    var activeModelURL: URL? {
        if let saved = defaults.string(forKey: selectedModelKey) {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            // Saved path no longer valid — clear it so we fall through
            defaults.removeObject(forKey: selectedModelKey)
        }
        return availableModels.first
    }

    var hasModel: Bool { activeModelURL != nil }

    func selectModel(_ url: URL) {
        defaults.set(url.path, forKey: selectedModelKey)
        AppLogger.log("Model selected: \(url.lastPathComponent)")
    }

    // Copies an external .bin file into modelsDirectory and selects it.
    func importModel(from source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let destination = modelsDirectory.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        selectModel(destination)
        AppLogger.log("Imported model: \(source.lastPathComponent)")
        return destination
    }

    // Returns true if the given catalog model is already present in the models folder.
    func isInstalled(_ model: DownloadableModel) -> Bool {
        FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(model.filename).path)
    }

    // Downloads a catalog model from its canonical URL, reports progress (0.0–1.0),
    // logs SHA-256 for manual verification, then moves the file into place atomically.
    // Large downloads use a long resource timeout so they don't hang silently on
    // a slow connection — they surface a clear "Connection timed out" instead.
    func downloadModel(_ model: DownloadableModel,
                       progress: @escaping (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destination = modelsDirectory.appendingPathComponent(model.filename)
        let tmpURL      = modelsDirectory.appendingPathComponent(model.filename + ".download")
        let sourceURL   = Self.resolvedURL(for: model)

        try? FileManager.default.removeItem(at: tmpURL)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30           // initial response
        config.timeoutIntervalForResource = 1800        // full download (30 min — turbo is 1.5 GB)
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)

        AppLogger.log("Downloading \(model.filename) from \(sourceURL.absoluteString)")

        let asyncBytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (asyncBytes, response) = try await session.bytes(from: sourceURL)
        } catch let urlError as URLError {
            throw DownloadError.network(urlError)
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.badResponse
        }

        let totalBytes = response.expectedContentLength
        var receivedBytes: Int64 = 0

        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: tmpURL) else {
            throw DownloadError.cannotWriteFile
        }

        var hasher = SHA256()
        for try await byte in asyncBytes {
            let chunk = Data([byte])
            fh.write(chunk)
            hasher.update(data: chunk)
            receivedBytes += 1
            if totalBytes > 0 && receivedBytes % 65536 == 0 {
                progress(Double(receivedBytes) / Double(totalBytes))
            }
        }
        try fh.close()
        progress(1.0)

        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        AppLogger.log("\(model.filename) SHA-256: \(hex)")

        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmpURL, to: destination)

        // Auto-select the newly downloaded model so it's immediately usable.
        selectModel(destination)
    }
}

// MARK: - Helpers

extension URL {
    // Human-readable file size, e.g. "142 MB"
    var fileSizeString: String {
        guard let bytes = (try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return "" }
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 1_000_000     { return String(format: "%.0f MB", Double(bytes) / 1e6) }
        return String(format: "%.0f KB", Double(bytes) / 1e3)
    }
}

enum DownloadError: Error, LocalizedError {
    case badResponse
    case cannotWriteFile
    case network(URLError)

    var errorDescription: String? {
        switch self {
        case .badResponse:     return "Server returned an error response"
        case .cannotWriteFile: return "Cannot write to models directory"
        case .network(let err):
            switch err.code {
            case .notConnectedToInternet:  return "No internet connection"
            case .timedOut:                return "Connection timed out"
            case .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed:         return "Cannot reach huggingface.co"
            case .networkConnectionLost:   return "Network connection was lost"
            case .cancelled:               return "Download was cancelled"
            default:                       return "Network error: \(err.localizedDescription)"
            }
        }
    }
}
