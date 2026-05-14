import Foundation

// Path-display helpers shared across the menu UI and log output.
enum PathFormatting {
    // Renders an absolute URL as a tilde-prefixed home-relative string when possible:
    //   /Users/alex/Documents/foo  →  ~/Documents/foo
    // Falls back to the absolute path when the URL is outside the home directory.
    static func friendly(_ url: URL) -> String {
        let home = NSHomeDirectory()
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}
