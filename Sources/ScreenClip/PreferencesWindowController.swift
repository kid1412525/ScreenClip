import Cocoa

final class PreferencesWindowController: NSWindowController {
    /// Set by AppDelegate: re-registers the stored shortcuts and reports
    /// whether the system accepted them.
    var onShortcutsChanged: (() -> Bool)?

    private let autoSaveCheckbox = NSButton(checkboxWithTitle: "スクリーンショットを撮ったら自動的に保存する", target: nil, action: nil)
    private let pathField = NSTextField(labelWithString: "")
    private var regionRecorder: ShortcutRecorderButton!
    private var fullScreenRecorder: ShortcutRecorderButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "環境設定"
        window.center()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        autoSaveCheckbox.target = self
        autoSaveCheckbox.action = #selector(autoSaveToggled)
        autoSaveCheckbox.state = PreferencesStore.autoSaveEnabled ? .on : .off

        let pathLabel = NSTextField(labelWithString: "保存先:")
        pathField.font = .systemFont(ofSize: 12)
        pathField.textColor = .secondaryLabelColor
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        updatePathField()

        let chooseButton = NSButton(title: "変更...", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded

        let resetButton = NSButton(title: "デフォルトに戻す", target: self, action: #selector(resetFolder))
        resetButton.bezelStyle = .rounded

        let pathRow = NSStackView(views: [pathLabel, pathField, chooseButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8

        let stack = NSStackView(views: [
            sectionLabel("保存"),
            autoSaveCheckbox,
            pathRow,
            resetButton,
            NSBox.horizontalSeparator(),
            sectionLabel("ショートカットキー"),
            shortcutRow("範囲を選択してキャプチャ:", recorder: makeRegionRecorder()),
            shortcutRow("画面全体をキャプチャ:", recorder: makeFullScreenRecorder()),
            shortcutHint(),
            resetShortcutsButton()
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor)
        ])
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - ショートカット設定

    private func makeRegionRecorder() -> ShortcutRecorderButton {
        let recorder = ShortcutRecorderButton(shortcut: PreferencesStore.regionShortcut)
        recorder.onShortcutRecorded = { [weak self] shortcut in
            self?.apply(shortcut, isRegion: true) ?? false
        }
        regionRecorder = recorder
        return recorder
    }

    private func makeFullScreenRecorder() -> ShortcutRecorderButton {
        let recorder = ShortcutRecorderButton(shortcut: PreferencesStore.fullScreenShortcut)
        recorder.onShortcutRecorded = { [weak self] shortcut in
            self?.apply(shortcut, isRegion: false) ?? false
        }
        fullScreenRecorder = recorder
        return recorder
    }

    /// Stores the new combination and asks AppDelegate to register it.
    /// Returns false (and leaves the button showing the old value) when the
    /// combination clashes with the other capture shortcut or the system
    /// refuses to hand it over.
    private func apply(_ shortcut: KeyboardShortcut, isRegion: Bool) -> Bool {
        let other = isRegion ? PreferencesStore.fullScreenShortcut : PreferencesStore.regionShortcut
        guard shortcut != other else {
            showFailure("もう一方のキャプチャと同じ組み合わせは設定できません。")
            return false
        }

        let previous = isRegion ? PreferencesStore.regionShortcut : PreferencesStore.fullScreenShortcut
        if isRegion {
            PreferencesStore.regionShortcut = shortcut
        } else {
            PreferencesStore.fullScreenShortcut = shortcut
        }

        // Registration is the only real test of whether the combination is
        // free, so a rejected one is rolled back rather than left stored.
        if onShortcutsChanged?() ?? true { return true }

        if isRegion {
            PreferencesStore.regionShortcut = previous
        } else {
            PreferencesStore.fullScreenShortcut = previous
        }
        _ = onShortcutsChanged?()
        showFailure("この組み合わせは他のアプリまたはシステムが使用中です。別のキーを選んでください。")
        return false
    }

    private func showFailure(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "このショートカットは使用できません"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func shortcutRow(_ title: String, recorder: ShortcutRecorderButton) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 180).isActive = true
        label.alignment = .right

        let row = NSStackView(views: [label, recorder])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func shortcutHint() -> NSTextField {
        let hint = NSTextField(wrappingLabelWithString:
            "ボタンを押してから新しいキーを入力してください（⌘・⌥・⌃のいずれかが必要、Escでキャンセル）。"
            + "macOS標準のスクリーンショットと同じ組み合わせは、システム設定 > キーボード > キーボードショートカット で無効にしてから設定してください。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 400
        return hint
    }

    private func resetShortcutsButton() -> NSButton {
        let button = NSButton(title: "ショートカットを初期値に戻す", target: self, action: #selector(resetShortcuts))
        button.bezelStyle = .rounded
        return button
    }

    @objc private func resetShortcuts() {
        PreferencesStore.regionShortcut = PreferencesStore.defaultRegionShortcut
        PreferencesStore.fullScreenShortcut = PreferencesStore.defaultFullScreenShortcut
        regionRecorder.shortcut = PreferencesStore.regionShortcut
        fullScreenRecorder.shortcut = PreferencesStore.fullScreenShortcut
        _ = onShortcutsChanged?()
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        return label
    }

    @objc private func autoSaveToggled() {
        PreferencesStore.autoSaveEnabled = autoSaveCheckbox.state == .on
    }

    @objc private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = PreferencesStore.saveDirectory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            PreferencesStore.saveDirectory = url
            self?.updatePathField()
        }
    }

    @objc private func resetFolder() {
        PreferencesStore.saveDirectory = PreferencesStore.defaultDirectory
        updatePathField()
    }

    private func updatePathField() {
        pathField.stringValue = PreferencesStore.saveDirectory.path
    }
}
