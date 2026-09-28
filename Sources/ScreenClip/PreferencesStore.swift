import Carbon
import Cocoa

enum PreferencesStore {
    private static let defaults = UserDefaults.standard
    private static let autoSaveKey = "autoSaveScreenshots"
    private static let saveDirectoryKey = "screenshotSaveDirectoryPath"
    private static let exportFormatKey = "lastExportFormat"
    private static let regionShortcutKey = "regionCaptureShortcut"
    private static let fullScreenShortcutKey = "fullScreenCaptureShortcut"

    static var autoSaveEnabled: Bool {
        get { defaults.bool(forKey: autoSaveKey) }
        set { defaults.set(newValue, forKey: autoSaveKey) }
    }

    static var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: saveDirectoryKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return defaultDirectory
        }
        set { defaults.set(newValue.path, forKey: saveDirectoryKey) }
    }

    /// The format last picked in the save panel, so the next save (and the
    /// one-click save button) starts from the same file type.
    static var lastExportFormat: ExportFormat {
        get {
            guard let raw = defaults.string(forKey: exportFormatKey) else { return .png }
            return ExportFormat(rawValue: raw) ?? .png
        }
        set { defaults.set(newValue.rawValue, forKey: exportFormatKey) }
    }

    // MARK: - Capture shortcuts

    /// ⌘⇧4 matches macOS's own "capture selection" shortcut for muscle
    /// memory; ⌘⇧F is free (⌘⇧3 is the system's full-screen capture).
    static let defaultRegionShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultFullScreenShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey))

    static var regionShortcut: KeyboardShortcut {
        get { shortcut(forKey: regionShortcutKey) ?? defaultRegionShortcut }
        set { defaults.set(newValue.rawValue, forKey: regionShortcutKey) }
    }

    static var fullScreenShortcut: KeyboardShortcut {
        get { shortcut(forKey: fullScreenShortcutKey) ?? defaultFullScreenShortcut }
        set { defaults.set(newValue.rawValue, forKey: fullScreenShortcutKey) }
    }

    private static func shortcut(forKey key: String) -> KeyboardShortcut? {
        defaults.string(forKey: key).flatMap(KeyboardShortcut.init(rawValue:))
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Matches macOS's own screenshot naming convention closely enough to
    /// be recognizable, e.g. "スクリーンショット 2026-08-21 2.33.47.png".
    static func generateFileName(format: ExportFormat = .png) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd H.mm.ss"
        return "スクリーンショット \(formatter.string(from: Date())).\(format.fileExtension)"
    }
}
