import AppKit

// Copies the transcribed text to the system clipboard and triggers a toast notification.
final class TextInserter {
    func insert(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let preview = text.count > 80 ? String(text.prefix(80)) + "…" : text
        Toast.show(title: "Copied to clipboard", body: preview, style: .success)
    }
}
