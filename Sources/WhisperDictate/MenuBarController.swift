import AppKit

// Owns the NSStatusItem (menu-bar icon) and the NSMenu attached to it.
// Reacts to AppState changes to update the icon and status line.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let state: AppState
    private let modelManager: ModelManager
    private weak var delegate: AppDelegate?

    // Menu items that need dynamic updates
    private let statusMenuItem  = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    private let toggleMenuItem  = NSMenuItem()
    private var modelSubmenu:    NSMenu!
    private var languageItems:   [WhisperLanguage: NSMenuItem] = [:]

    // One download menu item per catalog entry, keyed by model id
    private var downloadItems: [String: NSMenuItem] = [:]
    // Tracks the currently-downloading catalog id (for progress display + locking out concurrent downloads)
    private var activeDownloadID: String?

    // Tracks which menu items represent discovered model files
    private var modelFileItems: [NSMenuItem] = []

    // Recording blink animation
    private var blinkTimer:  Timer?
    private var blinkPhase   = false

    init(state: AppState, modelManager: ModelManager, delegate: AppDelegate) {
        self.state        = state
        self.modelManager = modelManager
        self.delegate     = delegate
        self.statusItem   = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        updateIcon(for: state.current)
        state.observe { [weak self] newState in
            self?.updateIcon(for: newState)
            self?.updateMenuItems(for: newState)
        }
    }

    // MARK: - Menu construction

    private func buildMenu() {
        let menu = NSMenu()

        // ── Status line ─────────────────────────────────────────────────────
        statusMenuItem.isEnabled = false
        statusMenuItem.attributedTitle = styledStatus("Idle")
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // ── Dictation toggle ─────────────────────────────────────────────────
        toggleMenuItem.title = "Start Dictation"
        toggleMenuItem.target = self
        toggleMenuItem.action = #selector(toggleDictation)
        toggleMenuItem.keyEquivalent = "d"
        toggleMenuItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())

        // ── Language selector ─────────────────────────────────────────────────
        let langParent = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu(title: "Language")
        for lang in WhisperLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, target: self, action: #selector(selectLanguage(_:)))
            item.representedObject = lang.rawValue
            item.state = (lang == WhisperLanguage.current) ? .on : .off
            langSubmenu.addItem(item)
            languageItems[lang] = item
        }
        langParent.submenu = langSubmenu
        menu.addItem(langParent)

        menu.addItem(.separator())

        // ── Model ──────────────────────────────────────────────────────────────
        let modelParent = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelSubmenu = NSMenu(title: "Model")
        modelSubmenu.delegate = self
        // Dynamic list (folder header + model entries + separator) is inserted by
        // rebuildModelList() before these static items every time the submenu opens.

        // One menu item per catalog entry. Title + tooltip reflect the source URL
        // so a security-minded user can audit where files come from. We store each
        // item keyed by id and update its title dynamically (e.g. "Downloading… 45%").
        for model in ModelManager.catalog {
            let item = NSMenuItem(
                title: downloadTitle(for: model, downloaded: false, progress: nil),
                target: self,
                action: #selector(downloadCatalogModel(_:))
            )
            item.representedObject = model.id
            item.toolTip = "Source: \(model.url.absoluteString)"
            modelSubmenu.addItem(item)
            downloadItems[model.id] = item
        }
        modelSubmenu.addItem(.separator())
        modelSubmenu.addItem(NSMenuItem(title: "Add Model File…", target: self, action: #selector(addModelFile)))
        modelSubmenu.addItem(NSMenuItem(title: "Open Models Folder", target: self, action: #selector(revealModels)))
        modelSubmenu.addItem(NSMenuItem(title: "Browse All whisper.cpp Models…", target: self, action: #selector(browseAllModels)))
        modelParent.submenu = modelSubmenu
        menu.addItem(modelParent)

        // ── Utilities ──────────────────────────────────────────────────────────
        menu.addItem(NSMenuItem(title: "Open Log", target: self, action: #selector(openLog)))
        menu.addItem(NSMenuItem(title: "Clear Log…", target: self, action: #selector(clearLog)))
        menu.addItem(NSMenuItem(title: "About WhisperDictate", target: self, action: #selector(showAbout)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", target: self, action: #selector(quit)))

        statusItem.menu = menu
    }

    private func styledStatus(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private func rebuildModelList() {
        // Remove old dynamic items
        for item in modelFileItems { modelSubmenu.removeItem(item) }
        modelFileItems.removeAll()

        let models = modelManager.availableModels
        let active = modelManager.activeModelURL
        var insertAt = 0

        // ── Folder location header (informational, disabled) ──
        // Renders the path in a friendly form: ~/Documents/WhisperDictate/Models
        // Uses an SF Symbol attachment for native sizing (emoji widths render
        // inconsistently across system font fallbacks).
        let dirHeader = NSMenuItem(title: PathFormatting.friendly(modelManager.modelsDirectory), action: nil, keyEquivalent: "")
        dirHeader.attributedTitle = folderHeaderAttributedString(
            path: PathFormatting.friendly(modelManager.modelsDirectory)
        )
        dirHeader.isEnabled = false
        modelSubmenu.insertItem(dirHeader, at: insertAt); insertAt += 1
        modelSubmenu.insertItem(.separator(), at: insertAt); insertAt += 1
        modelFileItems.append(dirHeader)
        modelFileItems.append(modelSubmenu.items[insertAt - 1])

        // ── Model list ──
        if models.isEmpty {
            let empty = NSMenuItem(title: "No models installed — use Download or Add Model File below", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            modelSubmenu.insertItem(empty, at: insertAt); insertAt += 1
            modelFileItems.append(empty)
        } else {
            for url in models {
                let isActive = (url.path == active?.path)
                let size = url.fileSizeString
                let label = size.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent)  ·  \(size)"
                let item = NSMenuItem(title: label, target: self, action: #selector(selectModelItem(_:)))
                item.representedObject = url
                item.state = isActive ? .on : .off
                if isActive {
                    // Bold the active entry — clearer at a glance than the checkmark alone.
                    item.attributedTitle = NSAttributedString(string: label, attributes: [
                        .font: NSFont.menuFont(ofSize: 0).bolded(),
                        .foregroundColor: NSColor.labelColor,
                    ])
                }
                modelSubmenu.insertItem(item, at: insertAt); insertAt += 1
                modelFileItems.append(item)
            }
        }

        // Trailing separator before the static actions
        let trailingSep = NSMenuItem.separator()
        modelSubmenu.insertItem(trailingSep, at: insertAt)
        modelFileItems.append(trailingSep)

        // Refresh each catalog download item's title to reflect installed state.
        // The actively-downloading model is left alone — its title is being driven
        // by the in-flight progress closure.
        for model in ModelManager.catalog where model.id != activeDownloadID {
            downloadItems[model.id]?.title = downloadTitle(
                for: model,
                downloaded: modelManager.isInstalled(model),
                progress: nil
            )
        }
    }

    // Renders the menu-item title for a catalog download in its various states.
    private func downloadTitle(for model: DownloadableModel,
                                downloaded: Bool,
                                progress: Int?) -> String {
        if let pct = progress {
            return "Downloading \(model.displayName)…  \(pct)%"
        }
        return downloaded
            ? "Re-download \(model.displayName)…"
            : "Download \(model.displayName) (\(model.approxSize))…"
    }

    // MARK: - Dynamic updates

    private func updateIcon(for state: AppStateValue) {
        guard let button = statusItem.button else { return }

        // Stop blink timer for any non-recording state
        if case .recording = state {} else {
            blinkTimer?.invalidate()
            blinkTimer = nil
            blinkPhase = false
            button.title = ""
            button.imagePosition = .imageOnly
        }

        #if DEBUG
        // Catch any future regression that would leave a wakeup timer running while idle.
        if case .recording = state {} else {
            assert(blinkTimer == nil, "blinkTimer must be nil outside .recording state")
        }
        #endif

        switch state {
        case .idle, .needsModel:
            button.image = icon("mic", color: .labelColor)
        case .recording:
            button.image = icon("mic.fill", color: .systemRed)
            setRecordingLabel(alpha: 1.0)
            button.imagePosition = .imageLeft
            // Blink with a smoothly-animated fade between alphas instead of a snap.
            // 0.9s period × 1 wakeup per tick is ~1.1 Hz of main-thread work — negligible.
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.blinkPhase.toggle()
                let target: CGFloat = self.blinkPhase ? 0.30 : 1.0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.85
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.setRecordingLabel(alpha: target)
                }
            }
        case .transcribing:
            button.image = icon("waveform", color: .systemOrange)
        case .error:
            button.image = icon("exclamationmark.triangle", color: .systemRed)
        }
    }

    private func setRecordingLabel(alpha: CGFloat) {
        statusItem.button?.attributedTitle = NSAttributedString(
            string: " ● REC",
            attributes: [
                .foregroundColor: NSColor.systemRed.withAlphaComponent(alpha),
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            ]
        )
    }

    private func updateMenuItems(for state: AppStateValue) {
        statusMenuItem.attributedTitle = styledStatus(state.displayName)
        switch state {
        case .recording:
            toggleMenuItem.title = "Stop Dictation"
        default:
            toggleMenuItem.title = "Start Dictation"
        }
        toggleMenuItem.isEnabled = (state != .transcribing)
    }

    private func icon(_ symbolName: String, color: NSColor) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img?.tinted(with: color)
    }

    // MARK: - Actions

    @objc private func toggleDictation() { delegate?.toggleDictation() }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = WhisperLanguage(rawValue: raw) else { return }
        WhisperLanguage.current = lang
        for (l, item) in languageItems { item.state = (l == lang) ? .on : .off }
        Toast.show(title: "Language", body: lang.displayName, style: .info)
    }

    @objc private func downloadCatalogModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let model = ModelManager.catalog.first(where: { $0.id == id }) else { return }

        // Refuse a second concurrent download — keeps the network behaviour predictable
        // and the menu UX clear about which item is in flight.
        if let active = activeDownloadID {
            let activeName = ModelManager.catalog.first(where: { $0.id == active })?.displayName ?? active
            Toast.show(title: "Another download is in progress",
                       body: "Wait for \(activeName) to finish", style: .info)
            return
        }

        activeDownloadID = id
        toggleMenuItem.isEnabled = false
        sender.title = downloadTitle(for: model, downloaded: false, progress: 0)
        Toast.show(title: "Downloading \(model.displayName)", body: model.approxSize, style: .info)

        Task {
            do {
                try await modelManager.downloadModel(model) { progress in
                    DispatchQueue.main.async { [weak self] in
                        let pct = Int(progress * 100)
                        self?.downloadItems[id]?.title = self?.downloadTitle(
                            for: model, downloaded: false, progress: pct
                        ) ?? ""
                    }
                }
                await MainActor.run {
                    activeDownloadID = nil
                    toggleMenuItem.isEnabled = true
                    state.set(.idle)
                    downloadItems[id]?.title = downloadTitle(for: model, downloaded: true, progress: nil)
                    Toast.show(title: "\(model.displayName) ready",
                               body: "Press ⌘⌥D to start dictating", style: .success)
                    AppLogger.log("Downloaded \(model.filename) successfully")
                }
            } catch {
                await MainActor.run {
                    activeDownloadID = nil
                    toggleMenuItem.isEnabled = true
                    downloadItems[id]?.title = downloadTitle(
                        for: model,
                        downloaded: modelManager.isInstalled(model),
                        progress: nil
                    )
                    Toast.show(title: "Download failed",
                               body: error.localizedDescription, style: .error)
                    AppLogger.log("Download of \(model.filename) failed: \(error)", level: .error)
                }
            }
        }
    }

    @objc private func browseAllModels() {
        // Source of truth for every ggml-converted whisper.cpp model the upstream maintainers ship.
        if let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/tree/main") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func selectModelItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        modelManager.selectModel(url)
        // Refresh checkmarks immediately
        let active = modelManager.activeModelURL
        for item in modelFileItems { item.state = ((item.representedObject as? URL)?.path == active?.path) ? .on : .off }
        state.set(.idle)
        Toast.show(title: "Model selected", body: url.lastPathComponent, style: .success)
    }

    @objc private func addModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Add whisper.cpp GGML model"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.message = "Choose a .bin file from whisper.cpp / ggerganov. The file will be copied into the models folder. Use the multilingual model (no 'en' suffix) for Turkish or German."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let dest = try modelManager.importModel(from: url)
            state.set(.idle)
            Toast.show(title: "Model added", body: dest.lastPathComponent, style: .success)
        } catch {
            Toast.show(title: "Import failed", body: error.localizedDescription, style: .error)
            AppLogger.log("Model import failed: \(error)", level: .error)
        }
    }

    @objc private func revealModels() {
        let dir = modelManager.modelsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(AppLogger.shared.logFileURL)
    }

    @objc private func clearLog() {
        let alert = NSAlert()
        alert.messageText = "Clear log file?"
        alert.informativeText = "This deletes all log entries from\n\(AppLogger.shared.logFileURL.path)"
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppLogger.shared.clearLog()
        Toast.show(title: "Log cleared", style: .info)
    }

    @objc private func showAbout() {
        AboutWindow.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // Programmatically open the menu (called when hotkey pressed with no model).
    func openModelSubmenu() {
        statusItem.button?.performClick(nil)
    }
}

// MARK: - NSMenuDelegate

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Only refresh the model submenu
        guard menu === modelSubmenu else { return }
        rebuildModelList()
    }
}

// MARK: - NSMenuItem convenience init
private extension NSMenuItem {
    convenience init(title: String, target: AnyObject?, action: Selector) {
        self.init(title: title, action: action, keyEquivalent: "")
        self.target = target
    }
}

// MARK: - NSImage tinting
private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}

// MARK: - NSFont bolded variant

private extension NSFont {
    func bolded() -> NSFont {
        let desc = fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: desc, size: pointSize) ?? self
    }
}

// MARK: - Folder header attributed string

private func folderHeaderAttributedString(path: String) -> NSAttributedString {
    let result = NSMutableAttributedString()

    // SF Symbol attachment for native look — sizes & aligns with the surrounding text.
    let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
    if let folder = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let attachment = NSTextAttachment()
        attachment.image = folder
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: "  "))
    }

    result.append(NSAttributedString(string: path, attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]))
    return result
}
