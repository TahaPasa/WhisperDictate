import Foundation

// Simple append-only logger. All writes happen on a private serial queue so it is
// safe to call from any thread. Output goes to a file in Application Support and to
// stderr (visible when launched from Terminal).
final class AppLogger {
    enum Level: String { case info = "INFO", warn = "WARN", error = "ERROR" }

    static let shared = AppLogger()
    private let queue = DispatchQueue(label: "com.whisperdictate.app.log")
    private var fileHandle: FileHandle?

    private static var logFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperDictate/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("whisper-dictate.log")
    }

    // When the active log file grows beyond this, it is rotated to .log.1 (older
    // rotated file is overwritten). Single-generation rotation keeps disk usage bounded.
    private static let rotateAtBytes: UInt64 = 1_000_000

    private init() {
        Self.rotateLogIfNeeded()
        let url = Self.logFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
    }

    // If the current log file exceeds the size cap, rename it to .log.1
    // (replacing any older rotated file) and start fresh.
    private static func rotateLogIfNeeded() {
        let url = logFileURL
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > rotateAtBytes else { return }

        let rotated = url.deletingPathExtension().appendingPathExtension("log.1")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: url, to: rotated)
    }

    static func log(_ message: String, level: Level = .info) {
        shared.write(message, level: level)
    }

    var logFileURL: URL { Self.logFileURL }

    // Truncates the log file to zero bytes (called from "Clear Log" menu item).
    func clearLog() {
        queue.async { [weak self] in
            self?.fileHandle?.truncateFile(atOffset: 0)
            self?.fileHandle?.seekToEndOfFile()
        }
        AppLogger.log("Log cleared by user")
    }

    private func write(_ message: String, level: Level) {
        let line = "\(iso8601()) [\(level.rawValue)] \(message)\n"
        queue.async { [weak self] in
            guard let data = line.data(using: .utf8) else { return }
            self?.fileHandle?.write(data)
            fputs(line, stderr)
        }
    }

    private func iso8601() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
