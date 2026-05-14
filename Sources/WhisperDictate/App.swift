import AppKit
import AVFoundation

// AppDelegate wires all subsystems together. It owns the object graph and drives
// the recording → transcription pipeline in response to hotkey presses.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state         = AppState()
    private let logger        = AppLogger.shared
    private let modelManager  = ModelManager()
    private var menuBar:       MenuBarController!
    private var hotkey:        HotkeyListener!
    private var recorder:      AudioRecorder!
    private var transcriber:   Transcriber!
    private let inserter       = TextInserter()

    func applicationDidFinishLaunching(_ note: Notification) {
        AppLogger.log("WhisperDictate starting")

        // Only one instance should run at a time. A second instance would register
        // its own menu-bar icon and lose the hotkey race; the user experience is
        // confusing. Detect and bail out cleanly.
        if isAnotherInstanceRunning() {
            AppLogger.log("Another WhisperDictate instance is already running — quitting", level: .warn)
            let alert = NSAlert()
            alert.messageText = "WhisperDictate is already running"
            alert.informativeText = "Click the microphone icon in the menu bar to use it."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        cleanupStaleTempFiles()

        // Carry forward settings from the previous (com.thakcygt.WhisperDictate)
        // bundle identifier so existing users do not lose their language/model choice.
        LaunchMigrations.migrateUserDefaultsFromLegacyBundle()

        // Move models from the legacy ~/Library/Application Support location
        // to the new user-visible ~/Documents/WhisperDictate/Models location.
        modelManager.migrateLegacyModelsIfNeeded()
        try? FileManager.default.createDirectory(at: modelManager.modelsDirectory, withIntermediateDirectories: true)

        recorder    = AudioRecorder(onCapReached: { [weak self] in self?.stopRecordingAndTranscribe() })
        transcriber = Transcriber(modelManager: modelManager)
        menuBar     = MenuBarController(state: state, modelManager: modelManager, delegate: self)

        hotkey = HotkeyListener { [weak self] in
            self?.toggleDictation()
        }
        let hotkeyResult = hotkey.register()
        if hotkeyResult != noErr {
            let msg = "⌘⌥D hotkey conflict (OSStatus \(hotkeyResult)). Another app may own it."
            AppLogger.log(msg, level: .error)
            state.set(.error(msg))
        }

        if modelManager.hasModel {
            state.set(.idle)
        } else {
            state.set(.needsModel)
        }

        // Force-stop recording when the system sleeps — AVAudioEngine will not
        // produce meaningful audio across a sleep/wake cycle and will sometimes hang.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )

        AppLogger.log("Ready. Model present: \(modelManager.hasModel)")
    }

    @objc private func systemWillSleep() {
        if case .recording = state.current {
            AppLogger.log("System sleeping — aborting recording", level: .warn)
            _ = try? recorder.stop()
            state.set(.idle)
            Toast.show(title: "Recording stopped", body: "System went to sleep", style: .info)
        }
    }

    // Presents a modal alert when AVCaptureDevice has denied microphone access.
    // The "Open Settings" button deep-links to the Microphone privacy pane so the
    // user does not have to hunt for it.
    private func showMicAccessDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone access is required"
        alert.informativeText = "WhisperDictate needs microphone access to transcribe your speech.\n\nOpen System Settings and enable WhisperDictate under Privacy & Security → Microphone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // Returns true when another running process advertises the same bundle ID.
    private func isAnotherInstanceRunning() -> Bool {
        guard let myBundleID = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == myBundleID && app.processIdentifier != mine
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        if case .recording = state.current {
            _ = try? recorder.stop()
        }
        hotkey.unregister()
        AppLogger.log("WhisperDictate stopped")
    }

    // MARK: - Security

    // Deletes any WAV files left in /tmp from a previous session that crashed mid-transcription.
    // Under normal operation these are deleted immediately after whisper-cli finishes (see Transcriber.swift).
    // Note: APFS uses Copy-on-Write, so byte-level overwrite is not possible; we delete promptly instead.
    private func cleanupStaleTempFiles() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil) else { return }
        let stale = files.filter { $0.lastPathComponent.hasPrefix("WhisperDictate-") && $0.pathExtension == "wav" }
        for url in stale {
            try? FileManager.default.removeItem(at: url)
            AppLogger.log("Cleaned up stale temp file: \(url.lastPathComponent)")
        }
        if !stale.isEmpty {
            AppLogger.log("Removed \(stale.count) stale recording(s) from previous session", level: .warn)
        }
    }

    // MARK: - Pipeline

    // Called by the hotkey AND by the "Start / Stop Dictation" menu item.
    func toggleDictation() {
        switch state.current {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .needsModel:
            menuBar.openModelSubmenu()
            Toast.show(title: "No model installed", body: "Use the menu to download one", style: .error)
        case .transcribing, .error:
            break  // ignore hotkey during these states
        }
    }

    private func startRecording() {
        // Request mic access lazily on first use (avoids a TCC prompt at launch).
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    do {
                        try self.recorder.start()
                        self.state.set(.recording)
                        AppLogger.log("Recording started")
                    } catch {
                        let msg = "Mic error: \(error.localizedDescription)"
                        AppLogger.log(msg, level: .error)
                        self.state.set(.error(msg))
                    }
                } else {
                    let msg = "Microphone access denied. Enable in System Settings → Privacy."
                    AppLogger.log(msg, level: .warn)
                    self.state.set(.error(msg))
                    self.showMicAccessDeniedAlert()
                }
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        guard case .recording = state.current else { return }
        do {
            let wavURL = try recorder.stop()
            state.set(.transcribing)
            AppLogger.log("Recording stopped, transcribing \(wavURL.lastPathComponent)")

            Task {
                do {
                    let text = try await transcriber.transcribe(wav: wavURL)
                    await MainActor.run {
                        if text.isEmpty {
                            Toast.show(title: "No speech detected", style: .info)
                            AppLogger.log("Transcription empty")
                        } else {
                            inserter.insert(text: text)
                            AppLogger.log("Transcribed \(text.count) chars")
                        }
                        state.set(.idle)
                    }
                } catch {
                    await MainActor.run {
                        let msg = "Transcription failed: \(error.localizedDescription)"
                        AppLogger.log(msg, level: .error)
                        state.set(.error(msg))
                        Toast.show(title: "Transcription failed", body: error.localizedDescription, style: .error)
                    }
                }
            }
        } catch {
            let msg = "Stop recording failed: \(error.localizedDescription)"
            AppLogger.log(msg, level: .error)
            state.set(.error(msg))
        }
    }
}
