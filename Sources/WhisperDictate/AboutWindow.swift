import AppKit

// Custom About panel. Replaces the generic NSApp.orderFrontStandardAboutPanel.
final class AboutWindow: NSObject {
    static let shared = AboutWindow()

    private var panel: NSPanel?

    func show() {
        if panel == nil { panel = build() }
        NSApp.activate(ignoringOtherApps: true)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Build

    // Project URL surfaced in About. Update once a public repo exists;
    // explicit constant so a security reviewer can audit it at a glance.
    private static let homepageURL = URL(string: "https://github.com/whisperdictate/whisperdictate")!

    private func build() -> NSPanel {
        let width: CGFloat = 360
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 420),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.title                = "WhisperDictate"
        p.isReleasedWhenClosed = false
        p.center()

        guard let cv = p.contentView else { return p }

        // ── Stack ────────────────────────────────────────────────────────
        let stack       = NSStackView()
        stack.orientation = .vertical
        stack.alignment   = .centerX
        stack.spacing     = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            stack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            stack.widthAnchor.constraint(equalToConstant: 320),
        ])

        // App icon
        let iconView = NSImageView()
        iconView.image        = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive  = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(iconView)
        stack.setCustomSpacing(10, after: iconView)

        // App name
        let nameLabel = label("WhisperDictate",
                               font: .systemFont(ofSize: 20, weight: .semibold),
                               color: .labelColor)
        nameLabel.alignment = .center
        stack.addArrangedSubview(nameLabel)
        stack.setCustomSpacing(4, after: nameLabel)

        // Version — read from Info.plist so we don't drift from CFBundleShortVersionString
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        let versionLabel = label("Version \(appVersion)  ·  macOS 13+",
                                  font: .systemFont(ofSize: 11),
                                  color: .secondaryLabelColor)
        versionLabel.alignment = .center
        stack.addArrangedSubview(versionLabel)
        stack.setCustomSpacing(16, after: versionLabel)

        stack.addArrangedSubview(separator())
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)

        // Description — kept tight so the panel stays compact.
        let descLabel = multilineLabel(
            "Your local dictation tool — free, secure, and private.\n\nNo cloud, no account, no corporate agreements. Bring your own whisper.cpp model or download one from the menu.",
            font: .systemFont(ofSize: 12),
            color: .labelColor
        )
        descLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(descLabel)
        stack.setCustomSpacing(10, after: descLabel)

        // Hotkey row
        let hotkeyLabel = label("⌘⌥D  ·  Start and stop dictation",
                                 font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                                 color: .secondaryLabelColor)
        hotkeyLabel.alignment = .center
        stack.addArrangedSubview(hotkeyLabel)
        stack.setCustomSpacing(10, after: hotkeyLabel)

        // Privacy badge — SF Symbol attachment for native styling
        let privacyColor = NSColor(red: 0.22, green: 0.82, blue: 0.40, alpha: 1)
        let privacyField = NSTextField(labelWithAttributedString: privacyBadgeString(color: privacyColor))
        privacyField.alignment = .center
        stack.addArrangedSubview(privacyField)
        stack.setCustomSpacing(14, after: privacyField)

        stack.addArrangedSubview(separator())
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        // Clickable GitHub homepage link
        let homepageBtn = linkButton(title: "GitHub",
                                      url: Self.homepageURL,
                                      action: #selector(openHomepage))
        stack.addArrangedSubview(homepageBtn)
        stack.setCustomSpacing(12, after: homepageBtn)

        // Footer
        let footerLabel = label("MIT License",
                                 font: .systemFont(ofSize: 10),
                                 color: .tertiaryLabelColor)
        footerLabel.alignment = .center
        stack.addArrangedSubview(footerLabel)
        stack.setCustomSpacing(16, after: footerLabel)

        // Close button — primary (Enter) plus Cmd+W also dismisses via window mechanics
        let closeBtn = NSButton(title: "Close", target: self, action: #selector(close))
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        stack.addArrangedSubview(closeBtn)
        stack.setCustomSpacing(20, after: closeBtn)

        // Cmd+W → close. Hidden invisible button serves as the key-equivalent target.
        let cmdW = NSButton(title: "", target: self, action: #selector(close))
        cmdW.keyEquivalent = "w"
        cmdW.keyEquivalentModifierMask = [.command]
        cmdW.isHidden = true
        cv.addSubview(cmdW)

        return p
    }

    // MARK: - Actions

    @objc private func close() { panel?.close() }
    @objc private func openHomepage() { NSWorkspace.shared.open(Self.homepageURL) }

    // MARK: - Helpers

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font      = font
        f.textColor = color
        return f
    }

    private func multilineLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font                   = font
        f.textColor              = color
        f.alignment              = .center
        f.maximumNumberOfLines   = 4
        return f
    }

    private func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 290).isActive = true
        return b
    }

    // Composes "🛡  No cloud. No account. No telemetry." with an SF Symbol
    // (lock.shield.fill) replacing the emoji for consistent rendering.
    private func privacyBadgeString(color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        if let shield = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let attachment = NSTextAttachment()
            attachment.image = shield
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "  "))
        }
        result.append(NSAttributedString(
            string: "No cloud. No account. No telemetry.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: color,
            ]
        ))
        return result
    }

    // Builds a discreet underlined-style link button. Uses a tinted attributedTitle
    // so the underline is visible without an enclosing bezel.
    private func linkButton(title: String, url: URL, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.bezelStyle = .inline
        btn.contentTintColor = .linkColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        btn.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        return btn
    }
}

// MARK: - NSTextField attributed-label convenience

private extension NSTextField {
    convenience init(labelWithAttributedString attributed: NSAttributedString) {
        self.init(labelWithString: "")
        self.attributedStringValue = attributed
        self.isBordered = false
        self.drawsBackground = false
        self.isEditable = false
        self.isSelectable = false
    }
}
