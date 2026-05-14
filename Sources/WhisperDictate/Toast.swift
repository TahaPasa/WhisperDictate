import AppKit

// Visual style of a toast notification.
enum ToastStyle {
    case success  // green checkmark — e.g. text copied
    case error    // red X          — e.g. mic denied, transcription failed
    case info     // blue mic       — e.g. language changed, model downloaded

    var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        case .info:    return "mic.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .success: return NSColor(red: 0.22, green: 0.82, blue: 0.40, alpha: 1)
        case .error:   return .systemRed
        case .info:    return NSColor(red: 0.40, green: 0.68, blue: 1.00, alpha: 1)
        }
    }
}

// A frosted-glass HUD that fades in at the bottom of the screen and auto-dismisses.
// Uses NSVisualEffectView (.hudWindow) for a native macOS look.
// No notification permission required.
final class Toast {
    private static let shared = Toast()

    // Title-only convenience (info style by default)
    static func show(text: String, style: ToastStyle = .info) {
        show(title: text, body: nil, style: style)
    }

    static func show(title: String, body: String? = nil, style: ToastStyle = .info) {
        DispatchQueue.main.async { shared.present(title: title, body: body, style: style) }
    }

    // MARK: - Private

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private func present(title: String, body: String?, style: ToastStyle) {
        hideWorkItem?.cancel()
        panel?.close()
        panel = nil

        let p = buildPanel(title: title, body: body, style: style)
        panel = p
        p.alphaValue = 0
        p.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1.0
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    private func dismiss() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.30
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.close()
            if self?.panel === p { self?.panel = nil }
        })
    }

    private func buildPanel(title: String, body: String?, style: ToastStyle) -> NSPanel {
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont  = NSFont.systemFont(ofSize: 11, weight: .regular)
        let hPad: CGFloat = 16
        let vPad: CGFloat = 11
        let iconSize: CGFloat = 20
        let iconGap:  CGFloat = 10
        let maxTextW: CGFloat = 320
        let textW = maxTextW - hPad * 2 - iconSize - iconGap

        // Measure title
        let titleH = ceil((title as NSString).boundingRect(
            with: NSSize(width: textW, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont]
        ).height)

        // Measure body
        var bodyH: CGFloat = 0
        if let b = body, !b.isEmpty {
            bodyH = ceil((b as NSString).boundingRect(
                with: NSSize(width: textW, height: 100),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: bodyFont]
            ).height)
        }

        let hasBody   = bodyH > 0
        let textH     = titleH + (hasBody ? 3 + bodyH : 0)
        let panelH    = max(vPad * 2 + max(textH, iconSize), 44)
        let panelW    = min(hPad * 2 + iconSize + iconGap + textW, 360)

        // Position: horizontally centered, 100pt from bottom of screen
        let screen   = NSScreen.main ?? NSScreen.screens[0]
        let sf       = screen.visibleFrame
        let x        = sf.midX - panelW / 2
        let y        = sf.minY + 100

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level          = .statusBar
        p.isOpaque       = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow      = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]

        // Frosted glass HUD background
        let blur = NSVisualEffectView(frame: NSRect(x:0, y:0, width:panelW, height:panelH))
        blur.material       = .hudWindow
        blur.blendingMode   = .behindWindow
        blur.state          = .active
        blur.wantsLayer     = true
        blur.layer?.cornerRadius   = 12
        blur.layer?.masksToBounds  = true
        p.contentView = blur

        // SF Symbol icon
        let iconCfg  = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        let iconImg  = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconCfg)
        let iconView = NSImageView()
        iconView.image            = iconImg
        iconView.contentTintColor = style.tintColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(iconView)

        // Title label
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font          = titleFont
        titleLabel.textColor     = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(titleLabel)

        var constraints: [NSLayoutConstraint] = [
            iconView.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: hPad),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: iconGap),
            titleLabel.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -hPad),
        ]

        if hasBody, let bodyText = body {
            let bodyLabel = NSTextField(labelWithString: bodyText)
            bodyLabel.font          = bodyFont
            bodyLabel.textColor     = NSColor.white.withAlphaComponent(0.65)
            bodyLabel.lineBreakMode = .byTruncatingTail
            bodyLabel.maximumNumberOfLines = 2
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(bodyLabel)
            constraints += [
                titleLabel.topAnchor.constraint(equalTo: blur.topAnchor, constant: vPad),
                iconView.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
                bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
                bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                bodyLabel.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -hPad),
            ]
        } else {
            constraints += [
                iconView.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return p
    }
}
