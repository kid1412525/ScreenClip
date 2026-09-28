import Carbon
import Cocoa
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var regionHotKey: HotKeyManager?
    private var fullScreenHotKey: HotKeyManager?
    private var resetIconWorkItem: DispatchWorkItem?
    private var editors: [EditorWindowController] = []
    private var preferencesWindowController: PreferencesWindowController?
    /// The window opened by the most recent capture — closed automatically
    /// when the next capture comes in, so screenshots don't pile up windows.
    /// Windows opened via "新しいウィンドウ" / ⌘O / paste / drag & drop are
    /// untouched by this.
    private weak var lastScreenshotEditor: EditorWindowController?
    private var regionMenuItem: NSMenuItem?
    private var fullScreenMenuItem: NSMenuItem?
    private var regionFileMenuItem: NSMenuItem?
    private var fullScreenFileMenuItem: NSMenuItem?

    private let idleIconName = "camera.viewfinder"
    private let successIconName = "checkmark.circle.fill"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()
        setupStatusItem()

        // These stay live even when ScreenClip is in the background, so a
        // capture can be started while working in another app. Both
        // combinations are configurable in 環境設定. If a system default for
        // the same combo is still enabled in System Settings > Keyboard >
        // Keyboard Shortcuts > Screenshots, both can fire at once — disable
        // it there to hand the combo fully to this app.
        regionHotKey = HotKeyManager(shortcut: PreferencesStore.regionShortcut) { [weak self] in
            self?.captureAndEdit(fullScreen: false)
        }
        fullScreenHotKey = HotKeyManager(shortcut: PreferencesStore.fullScreenShortcut) { [weak self] in
            self?.captureAndEdit(fullScreen: true)
        }

        // Carbon swallows a registered combination before the app sees it, so
        // the keys have to be released while 環境設定 records a new one.
        NotificationCenter.default.addObserver(
            forName: .shortcutRecordingBegan, object: nil, queue: .main
        ) { [weak self] _ in
            self?.regionHotKey?.unregister()
            self?.fullScreenHotKey?.unregister()
        }
        NotificationCenter.default.addObserver(
            forName: .shortcutRecordingEnded, object: nil, queue: .main
        ) { [weak self] _ in
            _ = self?.registerHotKeys()
        }

        // A plain double-click launch should behave like a normal editing
        // app — open a blank canvas right away instead of only showing the
        // menu bar icon. (applicationOpenUntitledFile isn't called here: it
        // only fires for apps that declare document types in Info.plist.)
        openEditor(with: makeBlankCanvas(), isPlaceholder: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon while the app is already running with every
    /// window closed should reopen a blank canvas, same as a fresh launch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openEditor(with: makeBlankCanvas(), isPlaceholder: true)
        }
        return true
    }

    // MARK: - Menu bar (main menu)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "ScreenClipについて", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(selfTargeted("環境設定...", ",", #selector(menuShowPreferences)))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "ScreenClipを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(selfTargeted("新しいウィンドウ", "n", #selector(menuNewWindow)))
        fileMenu.addItem(selfTargeted("開く...", "o", #selector(menuOpen)))
        fileMenu.addItem(selfTargeted("クリップボードから新規ウィンドウ", "v", #selector(menuNewFromClipboard), modifiers: [.command, .shift]))
        fileMenu.addItem(.separator())
        let regionFileItem = selfTargeted("範囲を選択してキャプチャ", "", #selector(menuCaptureRegion))
        let fullScreenFileItem = selfTargeted("画面全体をキャプチャ", "", #selector(menuCaptureFullScreen))
        fileMenu.addItem(regionFileItem)
        fileMenu.addItem(fullScreenFileItem)
        regionFileMenuItem = regionFileItem
        fullScreenFileMenuItem = fullScreenFileItem
        fileMenu.addItem(.separator())
        fileMenu.addItem(selfTargeted("名前を付けて保存...", "s", #selector(menuSave)))
        fileMenu.addItem(selfTargeted("保存先にすぐ保存", "s", #selector(menuQuickSave), modifiers: [.command, .shift]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "ウィンドウを閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "元に戻す", action: #selector(AnnotationCanvasView.undo(_:)), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "やり直す", action: #selector(AnnotationCanvasView.redo(_:)), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "画像をコピー", action: #selector(AnnotationCanvasView.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "貼り付け", action: #selector(AnnotationCanvasView.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "削除", action: #selector(AnnotationCanvasView.delete(_:)), keyEquivalent: ""))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(selfTargeted("全体表示", "0", #selector(menuZoomFit)))
        viewMenu.addItem(selfTargeted("実際のサイズ", "1", #selector(menuZoomActual)))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "すべてを手前に移動", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        updateShortcutMenuTitles()
    }

    private func selfTargeted(_ title: String, _ key: String, _ action: Selector, modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func keyEditor() -> EditorWindowController? {
        NSApp.keyWindow?.windowController as? EditorWindowController
    }

    @objc private func menuNewWindow() {
        openEditor(with: makeBlankCanvas(), isPlaceholder: true)
    }

    @objc private func menuOpen() {
        if let controller = keyEditor() {
            controller.openFile()
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            openEditor(with: image)
        }
    }

    @objc private func menuNewFromClipboard() {
        guard let image = NSImage(pasteboard: .general) else { return }
        openEditor(with: image)
    }

    @objc private func menuSave() {
        keyEditor()?.saveAs()
    }

    @objc private func menuQuickSave() {
        keyEditor()?.quickSave()
    }

    @objc private func menuCaptureRegion() {
        captureAndEdit(fullScreen: false)
    }

    @objc private func menuCaptureFullScreen() {
        captureAndEdit(fullScreen: true)
    }

    @objc private func menuZoomFit() {
        keyEditor()?.zoomToFit()
    }

    @objc private func menuZoomActual() {
        keyEditor()?.zoomToActual()
    }

    @objc private func menuShowPreferences() {
        if preferencesWindowController == nil {
            let controller = PreferencesWindowController()
            controller.onShortcutsChanged = { [weak self] in self?.registerHotKeys() ?? false }
            preferencesWindowController = controller
        }
        preferencesWindowController?.show()
    }

    /// Re-registers both capture shortcuts from what's stored. False means
    /// the system refused one of them (already taken by another app).
    @discardableResult
    private func registerHotKeys() -> Bool {
        let region = regionHotKey?.register(PreferencesStore.regionShortcut) ?? false
        let fullScreen = fullScreenHotKey?.register(PreferencesStore.fullScreenShortcut) ?? false
        updateShortcutMenuTitles()
        return region && fullScreen
    }

    /// Keeps both menus in step with the configured keys: the status item
    /// spells the combination out in its title, the File menu shows it as a
    /// real key equivalent.
    private func updateShortcutMenuTitles() {
        let region = PreferencesStore.regionShortcut
        let fullScreen = PreferencesStore.fullScreenShortcut

        regionMenuItem?.title = "選択範囲をキャプチャ (\(region.displayString))"
        fullScreenMenuItem?.title = "画面全体をキャプチャ (\(fullScreen.displayString))"

        for (item, shortcut) in [(regionFileMenuItem, region), (fullScreenFileMenuItem, fullScreen)] {
            guard let item else { continue }
            item.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
            item.keyEquivalentModifierMask = shortcut.menuModifierMask
        }
    }

    // MARK: - Status item (quick access even without any window open)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: idleIconName, accessibilityDescription: "ScreenClip")

        let menu = NSMenu()

        let regionItem = NSMenuItem(title: "選択範囲をキャプチャ", action: #selector(menuCaptureRegion), keyEquivalent: "")
        regionItem.target = self
        menu.addItem(regionItem)
        regionMenuItem = regionItem

        let fullItem = NSMenuItem(title: "画面全体をキャプチャ", action: #selector(menuCaptureFullScreen), keyEquivalent: "")
        fullItem.target = self
        menu.addItem(fullItem)
        fullScreenMenuItem = fullItem
        updateShortcutMenuTitles()

        menu.addItem(.separator())

        let newWindowItem = NSMenuItem(title: "新しいウィンドウ", action: #selector(menuNewWindow), keyEquivalent: "")
        newWindowItem.target = self
        menu.addItem(newWindowItem)

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: "環境設定...", action: #selector(menuShowPreferences), keyEquivalent: "")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Capture

    /// Captures either an interactively-picked region or the whole main
    /// screen to a temp PNG, copies it to the clipboard immediately (so the
    /// quick "capture → paste" workflow needs no extra steps), then opens it
    /// in the editor for annotation/adjustment.
    private func captureAndEdit(fullScreen: Bool) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenclip-\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = fullScreen ? [tmpURL.path] : ["-i", tmpURL.path]

        do {
            try task.run()
        } catch {
            NSLog("ScreenClip: failed to launch screencapture: \(error)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            task.waitUntilExit()

            // screencapture never creates the file if the user pressed Esc
            // during an interactive (region) capture.
            guard FileManager.default.fileExists(atPath: tmpURL.path),
                  let image = NSImage(contentsOf: tmpURL) else {
                return
            }
            try? FileManager.default.removeItem(at: tmpURL)

            if PreferencesStore.autoSaveEnabled {
                let destination = PreferencesStore.saveDirectory.appendingPathComponent(PreferencesStore.generateFileName())
                ImageExporter.write(image, to: destination)
            }

            DispatchQueue.main.async {
                PasteboardHelper.copy(image: image)
                self?.flashSuccess()
                self?.lastScreenshotEditor?.window?.close()
                self?.lastScreenshotEditor = self?.openEditor(with: image, activate: false)
            }
        }
    }

    @discardableResult
    private func openEditor(with image: NSImage, isPlaceholder: Bool = false, activate: Bool = true) -> EditorWindowController {
        var controller: EditorWindowController!
        controller = EditorWindowController(image: image, isPlaceholder: isPlaceholder) { [weak self] in
            self?.editors.removeAll { $0 === controller }
        }
        editors.append(controller)
        controller.show(activate: activate)
        return controller
    }

    private func makeBlankCanvas() -> NSImage {
        EditorWindowController.blankPlaceholderImage()
    }

    private func flashSuccess() {
        resetIconWorkItem?.cancel()
        statusItem.button?.image = NSImage(systemSymbolName: successIconName, accessibilityDescription: "Copied")
        NSSound(named: "Glass")?.play()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusItem.button?.image = NSImage(systemSymbolName: self.idleIconName, accessibilityDescription: "ScreenClip")
        }
        resetIconWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
}
