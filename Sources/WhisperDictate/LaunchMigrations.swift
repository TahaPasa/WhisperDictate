import Foundation

// One-time migrations that run on launch. Idempotent and guarded by a flag in
// UserDefaults so they only execute once per user.
enum LaunchMigrations {
    private static let didMigrateFromLegacyBundleKey = "didMigrateFromLegacyBundleV1"
    private static let legacyBundleID = "com.thakcygt.WhisperDictate"

    // Copies the user's previously-stored preferences (selected model, language)
    // from the legacy bundle identifier into the current one. Without this,
    // existing users would silently lose their settings after the rename.
    static func migrateUserDefaultsFromLegacyBundle() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didMigrateFromLegacyBundleKey) else { return }

        // Legacy prefs are stored at ~/Library/Preferences/<legacyBundleID>.plist.
        // UserDefaults(suiteName:) reads that plist directly when the suite name
        // matches a bundle identifier.
        guard let legacy = UserDefaults(suiteName: legacyBundleID) else {
            defaults.set(true, forKey: didMigrateFromLegacyBundleKey)
            return
        }

        let keysToCopy = ["whisperLanguage", "selectedModelPath", "customModelPath"]
        var copied: [String] = []
        for key in keysToCopy {
            if let value = legacy.object(forKey: key), defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
                copied.append(key)
            }
        }

        defaults.set(true, forKey: didMigrateFromLegacyBundleKey)

        if !copied.isEmpty {
            AppLogger.log("Migrated settings from legacy bundle: \(copied.joined(separator: ", "))")
        }
    }
}
