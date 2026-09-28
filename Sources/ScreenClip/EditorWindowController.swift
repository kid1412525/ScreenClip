import Cocoa
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let canvasDocument: CanvasDocument
    private let onWindowClose: () -> Void

    private var toolbarView: ToolbarView!
    private var canvasView: AnnotationCanvasView!
    private var scrollView: ZoomScrollView!
    private var adjustmentsPanel: AdjustmentsPanel!
    private var statusLabel: NSTextField!
    private var placeholderOverlay: NSView?
    private var clearImageButton: NSButton!
    private var suppressPlaceholderRemoval = false
    private let isPlaceholder: Bool

    init(image: NSImage, isPlaceholder: Bool = false, onWindowClose: @escaping () -> Void) {
        self.canvasDocument = CanvasDocument(image: image)
        self.isPlaceholder = isPlaceholder
        self.onWindowClose = onWindowClose

        // Side panels scroll internally (see setupUI), so this only needs to
        // keep the overall window from growing past the screen — it doesn't
        // need to reserve enough room for the panels' full content height.
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1400, height: 900)
        let chromeWidth: CGFloat = 60 + 220
        let chromeHeight: CGFloat = 24 + 40 // status bar + titlebar allowance
        let maxContentWidth = visible.width - 40
        let maxContentHeight = visible.height - 40

        let canvasWidth = min(image.size.width, maxContentWidth - chromeWidth)
        let canvasHeight = min(image.size.height, maxContentHeight - chromeHeight)
        let contentWidth = min(max(canvasWidth, 480) + chromeWidth, maxContentWidth)
        let contentHeight = min(max(canvasHeight, 320) + chromeHeight, maxContentHeight)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "スクリーンショットを編集"
        window.center()

        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window, let contentView = window.contentView else { return }

        toolbarView = ToolbarView(frame: .zero)
        canvasView = AnnotationCanvasView(document: canvasDocument)

        scrollView = ZoomScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        scrollView.documentView = canvasView

        adjustmentsPanel = AdjustmentsPanel(frame: .zero)

        // Both side panels can be taller than the window (many tools, or a
        // short/wide screenshot leaving little vertical room) — wrapping
        // them in their own scroll view keeps every control reachable
        // instead of silently clipping whatever doesn't fit.
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        let toolbarScroll = NSScrollView()
        toolbarScroll.hasVerticalScroller = true
        toolbarScroll.hasHorizontalScroller = false
        toolbarScroll.drawsBackground = false
        toolbarScroll.contentView = TopAligningClipView()
        toolbarScroll.documentView = toolbarView

        adjustmentsPanel.translatesAutoresizingMaskIntoConstraints = false
        let adjustmentsScroll = NSScrollView()
        adjustmentsScroll.hasVerticalScroller = true
        adjustmentsScroll.hasHorizontalScroller = false
        adjustmentsScroll.drawsBackground = false
        adjustmentsScroll.contentView = TopAligningClipView()
        adjustmentsScroll.documentView = adjustmentsPanel

        statusLabel = NSTextField(labelWithString: "範囲をドラッグして描画、選択ツール(V)でクリックして編集、Deleteで削除できます。")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let statusBar = NSView()

        for view in [toolbarScroll, scrollView, adjustmentsScroll, statusBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            toolbarScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbarScroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbarScroll.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            toolbarScroll.widthAnchor.constraint(equalToConstant: 60),
            toolbarView.leadingAnchor.constraint(equalTo: toolbarScroll.contentView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: toolbarScroll.contentView.trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: toolbarScroll.contentView.topAnchor),

            adjustmentsScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            adjustmentsScroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            adjustmentsScroll.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            adjustmentsScroll.widthAnchor.constraint(equalToConstant: 220),
            adjustmentsPanel.leadingAnchor.constraint(equalTo: adjustmentsScroll.contentView.leadingAnchor),
            adjustmentsPanel.trailingAnchor.constraint(equalTo: adjustmentsScroll.contentView.trailingAnchor),
            adjustmentsPanel.topAnchor.constraint(equalTo: adjustmentsScroll.contentView.topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: toolbarScroll.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: adjustmentsScroll.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 10),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])

        setupClearImageButton()
        wireCallbacks()
        if isPlaceholder {
            addPlaceholderOverlay()
        }
    }

    /// Shown only on the blank canvas opened at launch / "新しいウィンドウ",
    /// so picking a file is one visible click instead of only being
    /// reachable via ⌘O or drag & drop.
    private func addPlaceholderOverlay() {
        guard let window, let contentView = window.contentView else { return }

        let button = NSButton(title: "ファイルを選択...", target: self, action: #selector(placeholderOpenTapped))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 14, weight: .medium)

        let hint = NSTextField(labelWithString: "またはドラッグ&ドロップ / ⌘V で貼り付け")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [button, hint])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        placeholderOverlay = stack
        clearImageButton.isHidden = true
    }

    @objc private func placeholderOpenTapped() {
        openFile()
    }

    private func removePlaceholderOverlayIfNeeded() {
        guard let placeholderOverlay else { return }
        placeholderOverlay.removeFromSuperview()
        self.placeholderOverlay = nil
        clearImageButton.isHidden = false
    }

    /// A small always-present "✕" over the canvas so a loaded image can be
    /// discarded without closing the window — swaps back to a blank,
    /// transparent placeholder and brings the file-picker button back.
    private func setupClearImageButton() {
        guard let contentView = window?.contentView else { return }

        let button = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "画像をクリア") ?? NSImage(),
            target: self,
            action: #selector(clearImageTapped)
        )
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "画像をクリアして選び直す"
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])

        button.isHidden = isPlaceholder
        clearImageButton = button
    }

    @objc private func clearImageTapped() {
        suppressPlaceholderRemoval = true
        canvasDocument.replaceImage(Self.blankPlaceholderImage())
        suppressPlaceholderRemoval = false
        if placeholderOverlay == nil {
            addPlaceholderOverlay()
        }
    }

    static func blankPlaceholderImage() -> NSImage {
        let size = NSSize(width: 900, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private func wireCallbacks() {
        canvasView.onDocumentChanged = { [weak self] in
            guard let self else { return }
            self.adjustmentsPanel.adjustments = self.canvasDocument.adjustments
            if !self.suppressPlaceholderRemoval {
                self.removePlaceholderOverlayIfNeeded()
            }
        }
        canvasView.onToolChanged = { [weak self] tool in
            guard let self else { return }
            self.toolbarView.setActiveTool(tool)
            self.setStatus(self.hint(for: tool))
        }
        canvasView.onSelectionChanged = { [weak self] annotation in
            guard let self else { return }
            let style = annotation?.annotationStyle ?? self.canvasView.style
            self.toolbarView.setStyle(color: style.color, width: style.lineWidth, fontSize: style.fontSize)
        }
        canvasView.onTextInsertRequested = { [weak self] point in
            self?.promptForText(existing: nil, insertAt: point)
        }
        canvasView.onTextEditRequested = { [weak self] text in
            self?.promptForText(existing: text, insertAt: nil)
        }
        canvasView.onImageDropped = { [weak self] image in
            self?.canvasDocument.replaceImage(image)
        }
        canvasView.onCopied = { [weak self] in
            self?.setStatus("編集後の画像をクリップボードにコピーしました。")
        }

        toolbarView.onToolSelected = { [weak self] tool in
            guard let self else { return }
            self.canvasView.tool = tool
            self.setStatus(self.hint(for: tool))
            self.window?.makeFirstResponder(self.canvasView)
        }
        toolbarView.onColorChanged = { [weak self] color in
            guard let self else { return }
            self.canvasView.style.color = color
            self.applyStyleToSelection { $0.color = color }
        }
        toolbarView.onWidthChanged = { [weak self] width in
            guard let self else { return }
            self.canvasView.style.lineWidth = width
            self.applyStyleToSelection { $0.lineWidth = width }
        }
        toolbarView.onFontSizeChanged = { [weak self] size in
            guard let self else { return }
            self.canvasView.style.fontSize = size
            self.applyStyleToSelection { $0.fontSize = size }
        }

        adjustmentsPanel.adjustments = canvasDocument.adjustments
        adjustmentsPanel.onAdjustmentsChanged = { [weak self] adjustments in
            self?.canvasDocument.adjustments = adjustments
        }
        adjustmentsPanel.onRotate = { [weak self] clockwise in
            self?.canvasDocument.rotate(clockwise: clockwise)
        }
        adjustmentsPanel.onFlip = { [weak self] horizontal in
            self?.canvasDocument.flip(horizontal: horizontal)
        }
        adjustmentsPanel.onResizeRequested = { [weak self] in
            self?.activateBoundsTool(.resize)
        }
        adjustmentsPanel.onCropRequested = { [weak self] in
            self?.activateBoundsTool(.crop)
        }
        adjustmentsPanel.onSaveRequested = { [weak self] in
            self?.saveAs()
        }
        adjustmentsPanel.onQuickSaveRequested = { [weak self] in
            self?.quickSave()
        }
        adjustmentsPanel.onCopyRequested = { [weak self] in
            self?.copyToClipboard()
        }
    }

    private func activateBoundsTool(_ tool: EditorTool) {
        canvasView.tool = tool
        toolbarView.setActiveTool(tool)
        setStatus(hint(for: tool))
        window?.makeFirstResponder(canvasView)
    }

    private func applyStyleToSelection(_ mutate: (inout AnnotationStyle) -> Void) {
        guard let selected = canvasView.selected, var style = selected.annotationStyle else { return }
        canvasDocument.pushUndo()
        mutate(&style)
        selected.annotationStyle = style
        canvasDocument.notifyChanged()
    }

    private func hint(for tool: EditorTool) -> String {
        switch tool {
        case .select: return "クリックして選択、ドラッグで移動、ハンドルでリサイズ、Deleteで削除できます。"
        case .pan: return "ドラッグして表示位置を動かせます。"
        case .crop: return "ハンドルをドラッグして切り抜く範囲を調整し、Returnで確定・Escでキャンセルします。"
        case .resize: return "ハンドルをドラッグして画像サイズを変え、Returnで確定・Escでキャンセルします。"
        case .text: return "クリックした位置にテキストを追加します。色と文字サイズはダイアログで選べます。"
        default: return "ドラッグして描画します。色と太さは左下で選べます。"
        }
    }

    /// activate: false shows the window without switching away from
    /// whatever app the user is currently in — used after a hotkey capture
    /// so grabbing a screenshot doesn't yank focus off their current work.
    func show(activate: Bool = true) {
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFront(nil)
        }
        window?.makeFirstResponder(canvasView)

        // A full-screen capture is often bigger than the window, which
        // otherwise opens at 100% and shows only a corner of it — fit the
        // whole screenshot in view right away instead of leaving that to a
        // manual ⌘0.
        window?.contentView?.layoutSubtreeIfNeeded()
        zoomToFit()
    }

    // MARK: - Menu-routed actions (invoked by AppDelegate via the key window)

    func openFile() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url), let self else { return }
            self.canvasDocument.replaceImage(image)
        }
    }

    func saveAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        let initialFormat = PreferencesStore.lastExportFormat

        // The format popup drives both the panel's allowed type and the
        // name field's extension, so picking PNG vs JPEG here is what
        // decides how the file is actually encoded.
        let picker = ExportFormatPicker()
        picker.format = initialFormat
        picker.onFormatChanged = { [weak panel] format in
            guard let panel else { return }
            panel.allowedContentTypes = [format.contentType]
            let name = panel.nameFieldStringValue as NSString
            // "スクリーンショット 2026-08-21 2.33.47" has no extension but does
            // have dots, so only strip a suffix that really is an image one.
            let base = ExportFormat.knownExtensions.contains(name.pathExtension.lowercased())
                ? name.deletingPathExtension
                : (name as String)
            panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
        }

        panel.accessoryView = picker
        panel.allowedContentTypes = [initialFormat.contentType]
        panel.nameFieldStringValue = PreferencesStore.generateFileName(format: initialFormat)
        panel.canSelectHiddenExtension = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            // Read the format back off the final URL rather than the popup:
            // the panel has the last word on the extension it settles on.
            let format = ExportFormat.matching(extension: url.pathExtension)
            PreferencesStore.lastExportFormat = format
            if ImageExporter.write(self.canvasDocument.flattenedForExport(), to: url, format: format) {
                self.setStatus("保存しました: \(url.lastPathComponent)")
            } else {
                self.setStatus("保存に失敗しました。")
            }
        }
    }

    /// Writes the current image straight into the folder set in 環境設定,
    /// with a generated name and the last-used format — no dialog.
    func quickSave() {
        let format = PreferencesStore.lastExportFormat
        let directory = PreferencesStore.saveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(PreferencesStore.generateFileName(format: format))
        if ImageExporter.write(canvasDocument.flattenedForExport(), to: url, format: format) {
            setStatus("保存しました: \(url.path)")
        } else {
            setStatus("保存に失敗しました: \(directory.path) に書き込めません。")
        }
    }

    /// Routed through the canvas so the button and ⌘C behave identically.
    func copyToClipboard() {
        canvasView.copy(nil)
    }

    func zoomToFit() {
        let visible = scrollView.bounds.size
        let docSize = canvasDocument.canvasSize
        guard docSize.width > 0, docSize.height > 0 else { return }
        let scale = min(visible.width / docSize.width, visible.height / docSize.height, 1.0)
        scrollView.magnification = max(scale, scrollView.minMagnification)
    }

    func zoomToActual() {
        scrollView.magnification = 1.0
    }

    // MARK: - Dialogs

    private func promptForText(existing: TextAnnotation?, insertAt point: NSPoint?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = existing == nil ? "テキストを追加" : "テキストを編集"
        alert.addButton(withTitle: existing == nil ? "追加" : "更新")
        alert.addButton(withTitle: "キャンセル")

        // Editing starts from the annotation's own style; a new one starts
        // from the current drawing style (i.e. what the toolbar shows).
        let baseStyle = existing?.style ?? canvasView.style

        let field = NSTextField(frame: NSRect(x: 0, y: 32, width: 320, height: 24))
        field.stringValue = existing?.text ?? ""
        field.autoresizingMask = [.width]

        let colorWell = NSColorWell()
        colorWell.color = baseStyle.color
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let sizePopup = NSPopUpButton()
        sizePopup.addItems(withTitles: AnnotationStyle.fontSizeChoices.map { String(Int($0)) })
        sizePopup.selectItem(at: AnnotationStyle.nearestFontSizeIndex(to: baseStyle.fontSize))

        let styleRow = NSStackView(views: [
            dialogLabel("色"), colorWell, dialogLabel("文字サイズ"), sizePopup
        ])
        styleRow.orientation = .horizontal
        styleRow.spacing = 6
        styleRow.frame = NSRect(x: 0, y: 0, width: 320, height: 26)
        styleRow.autoresizingMask = [.width]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 58))
        container.addSubview(field)
        container.addSubview(styleRow)

        alert.accessoryView = container
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }

            var style = baseStyle
            style.color = colorWell.color
            style.fontSize = AnnotationStyle.fontSizeChoices[max(sizePopup.indexOfSelectedItem, 0)]

            // What was picked here sticks as the drawing style, so the next
            // text starts from it — same shared style the toolbar edits.
            self.canvasView.style.color = style.color
            self.canvasView.style.fontSize = style.fontSize
            self.toolbarView.setStyle(
                color: style.color,
                width: self.canvasView.style.lineWidth,
                fontSize: style.fontSize
            )

            if let existing {
                self.canvasDocument.pushUndo()
                existing.text = field.stringValue
                existing.style = style
                self.canvasDocument.notifyChanged()
            } else if let point {
                let annotation = TextAnnotation(origin: point, text: field.stringValue, style: style)
                self.canvasDocument.addAnnotation(annotation)
            }
        }
    }

    private func dialogLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClose()
    }
}
