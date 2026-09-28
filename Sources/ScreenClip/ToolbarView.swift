import Cocoa

/// A plain NSButton that reports hover in/out, used so the toolbar can show
/// an instant name/shortcut hint instead of waiting on the OS tooltip delay.
final class ToolButton: NSButton {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

final class ToolbarView: NSView {
    var onToolSelected: ((EditorTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onWidthChanged: ((CGFloat) -> Void)?
    var onFontSizeChanged: ((CGFloat) -> Void)?

    private var toolButtons: [EditorTool: ToolButton] = [:]
    private let hoverLabel = NSTextField(labelWithString: " ")
    private let colorWell = NSColorWell()
    private let widthPopup = NSPopUpButton()
    private let widths: [CGFloat] = [2, 4, 8, 14]
    private let fontSizePopup = NSPopUpButton()
    private let fontSizes = AnnotationStyle.fontSizeChoices

    private let toolOrder: [EditorTool] = [
        .select, .pan, .crop,
        .pen, .marker, .line, .arrow, .rectangle, .ellipse, .text,
        .mosaic, .blur
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        hoverLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hoverLabel.textColor = .secondaryLabelColor
        hoverLabel.alignment = .center
        hoverLabel.maximumNumberOfLines = 2
        hoverLabel.lineBreakMode = .byWordWrapping
        hoverLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        hoverLabel.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        stack.addArrangedSubview(hoverLabel)
        stack.addArrangedSubview(NSBox.horizontalSeparator())

        for tool in toolOrder {
            let button = ToolButton(
                image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.label) ?? NSImage(),
                target: self,
                action: #selector(toolButtonTapped(_:))
            )
            button.bezelStyle = .rounded
            button.setButtonType(.pushOnPushOff)
            button.toolTip = "\(tool.label)\(tool.shortcutKey.isEmpty ? "" : " (\(tool.shortcutKey.uppercased()))")"
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            button.onHover = { [weak self] entered in
                self?.hoverLabel.stringValue = entered ? button.toolTip ?? tool.label : " "
            }
            toolButtons[tool] = button
            stack.addArrangedSubview(button)

            if tool == .crop || tool == .text {
                stack.addArrangedSubview(NSBox.horizontalSeparator())
            }
        }

        let colorLabel = NSTextField(labelWithString: "色")
        colorLabel.font = .systemFont(ofSize: 10)
        colorLabel.textColor = .secondaryLabelColor
        colorLabel.alignment = .center

        colorWell.color = AnnotationStyle.default.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.toolTip = "描画する色（選択中の図形にも反映されます）"
        colorWell.widthAnchor.constraint(equalToConstant: 36).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let widthLabel = NSTextField(labelWithString: "太さ")
        widthLabel.font = .systemFont(ofSize: 10)
        widthLabel.textColor = .secondaryLabelColor
        widthLabel.alignment = .center

        widthPopup.addItems(withTitles: ["細", "標準", "太い", "極太"])
        widthPopup.selectItem(at: 1)
        widthPopup.target = self
        widthPopup.action = #selector(widthChanged)
        widthPopup.toolTip = "線の太さ（選択中の図形にも反映されます）"
        widthPopup.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let fontSizeLabel = NSTextField(labelWithString: "文字")
        fontSizeLabel.font = .systemFont(ofSize: 10)
        fontSizeLabel.textColor = .secondaryLabelColor
        fontSizeLabel.alignment = .center

        fontSizePopup.addItems(withTitles: fontSizes.map { String(Int($0)) })
        fontSizePopup.selectItem(at: AnnotationStyle.nearestFontSizeIndex(to: AnnotationStyle.default.fontSize))
        fontSizePopup.target = self
        fontSizePopup.action = #selector(fontSizeChanged)
        fontSizePopup.toolTip = "テキストの文字サイズ（選択中のテキストにも反映されます）"
        fontSizePopup.widthAnchor.constraint(equalToConstant: 64).isActive = true

        stack.addArrangedSubview(NSBox.horizontalSeparator())
        stack.addArrangedSubview(colorLabel)
        stack.addArrangedSubview(colorWell)
        stack.addArrangedSubview(widthLabel)
        stack.addArrangedSubview(widthPopup)
        stack.addArrangedSubview(fontSizeLabel)
        stack.addArrangedSubview(fontSizePopup)

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Pinning the bottom too (rather than leaving it free) makes
            // this view's height fully driven by the stack's own content,
            // which is what lets it sit inside a scroll view correctly.
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setActiveTool(.select)
    }

    @objc private func toolButtonTapped(_ sender: NSButton) {
        guard let tool = toolOrder.first(where: { toolButtons[$0] === sender }) else { return }
        setActiveTool(tool)
        onToolSelected?(tool)
    }

    @objc private func colorChanged() {
        onColorChanged?(colorWell.color)
    }

    @objc private func widthChanged() {
        onWidthChanged?(widths[widthPopup.indexOfSelectedItem])
    }

    @objc private func fontSizeChanged() {
        onFontSizeChanged?(fontSizes[fontSizePopup.indexOfSelectedItem])
    }

    func setActiveTool(_ tool: EditorTool) {
        for (t, button) in toolButtons {
            button.state = (t == tool) ? .on : .off
        }
    }

    /// Reflects either the current drawing default or the selected
    /// annotation's own style — see EditorWindowController's wiring.
    func setStyle(color: NSColor, width: CGFloat, fontSize: CGFloat) {
        colorWell.color = color
        if let index = widths.firstIndex(of: width) {
            widthPopup.selectItem(at: index)
        }
        fontSizePopup.selectItem(at: AnnotationStyle.nearestFontSizeIndex(to: fontSize))
    }
}

extension NSBox {
    static func horizontalSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
