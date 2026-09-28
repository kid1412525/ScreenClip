import Cocoa

final class AdjustmentsPanel: NSView {
    var adjustments = ImageAdjustments() {
        didSet { syncSliders() }
    }

    var onAdjustmentsChanged: ((ImageAdjustments) -> Void)?
    var onRotate: ((Bool) -> Void)?
    var onFlip: ((Bool) -> Void)?
    var onResizeRequested: (() -> Void)?
    var onCropRequested: (() -> Void)?
    var onSaveRequested: (() -> Void)?
    var onQuickSaveRequested: (() -> Void)?
    var onCopyRequested: (() -> Void)?

    private let brightnessSlider = LabeledSlider(title: "明るさ", min: -1, max: 1)
    private let contrastSlider = LabeledSlider(title: "コントラスト", min: 0, max: 2)
    private let saturationSlider = LabeledSlider(title: "彩度", min: 0, max: 2)
    private let hueSlider = LabeledSlider(title: "色相", min: -Double.pi, max: Double.pi)
    private let sharpnessSlider = LabeledSlider(title: "シャープ", min: 0, max: 2)
    private let blurSlider = LabeledSlider(title: "ぼかし", min: 0, max: 20)
    private let grayscaleCheckbox = NSButton(checkboxWithTitle: "白黒", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        for slider in [brightnessSlider, contrastSlider, saturationSlider, hueSlider, sharpnessSlider, blurSlider] {
            slider.onChanged = { [weak self] _ in self?.pushAdjustments() }
        }
        grayscaleCheckbox.target = self
        grayscaleCheckbox.action = #selector(pushAdjustments)

        let rotateCW = iconButton("rotate.right", tooltip: "右に90度回転", action: #selector(rotateCWTapped))
        let rotateCCW = iconButton("rotate.left", tooltip: "左に90度回転", action: #selector(rotateCCWTapped))
        let flipH = iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", tooltip: "左右反転", action: #selector(flipHTapped))
        let flipV = iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", tooltip: "上下反転", action: #selector(flipVTapped))
        let transformRow = NSStackView(views: [rotateCCW, rotateCW, flipH, flipV])
        transformRow.orientation = .horizontal
        transformRow.spacing = 6

        let resizeButton = NSButton(title: "サイズ変更", target: self, action: #selector(resizeTapped))
        let cropButton = NSButton(title: "切り抜き (C)", target: self, action: #selector(cropTapped))
        let resetButton = NSButton(title: "調整をリセット", target: self, action: #selector(resetTapped))
        for button in [resizeButton, cropButton, resetButton] {
            button.bezelStyle = .rounded
        }

        let saveAsButton = NSButton(title: "保存... (⌘S)", target: self, action: #selector(saveTapped))
        saveAsButton.toolTip = "ファイル名と拡張子（PNG/JPEG/TIFFなど）を選んで書き出します"
        let quickSaveButton = NSButton(title: "すぐ保存 (⌘⇧S)", target: self, action: #selector(quickSaveTapped))
        quickSaveButton.toolTip = "環境設定の保存先に、そのまま書き出します"
        let copyButton = NSButton(title: "画像をコピー (⌘C)", target: self, action: #selector(copyTapped))
        copyButton.toolTip = "編集後の画像をクリップボードにコピーします"
        for button in [saveAsButton, quickSaveButton, copyButton] {
            button.bezelStyle = .rounded
        }

        let stack = NSStackView(views: [
            sectionLabel("書き出し"),
            saveAsButton,
            quickSaveButton,
            copyButton,
            NSBox.horizontalSeparator(),
            sectionLabel("色調整"),
            brightnessSlider, contrastSlider, saturationSlider, hueSlider, sharpnessSlider, blurSlider,
            grayscaleCheckbox,
            resetButton,
            NSBox.horizontalSeparator(),
            sectionLabel("変形"),
            transformRow,
            resizeButton,
            cropButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
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
    }

    private func iconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .rounded
        button.toolTip = tooltip
        return button
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        return label
    }

    private func syncSliders() {
        brightnessSlider.value = adjustments.brightness
        contrastSlider.value = adjustments.contrast
        saturationSlider.value = adjustments.saturation
        hueSlider.value = adjustments.hue
        sharpnessSlider.value = adjustments.sharpness
        blurSlider.value = adjustments.blur
        grayscaleCheckbox.state = adjustments.grayscale ? .on : .off
    }

    @objc private func pushAdjustments() {
        var next = adjustments
        next.brightness = brightnessSlider.value
        next.contrast = contrastSlider.value
        next.saturation = saturationSlider.value
        next.hue = hueSlider.value
        next.sharpness = sharpnessSlider.value
        next.blur = blurSlider.value
        next.grayscale = grayscaleCheckbox.state == .on
        adjustments = next
        onAdjustmentsChanged?(adjustments)
    }

    @objc private func rotateCWTapped() { onRotate?(true) }
    @objc private func rotateCCWTapped() { onRotate?(false) }
    @objc private func flipHTapped() { onFlip?(true) }
    @objc private func flipVTapped() { onFlip?(false) }
    @objc private func resizeTapped() { onResizeRequested?() }
    @objc private func cropTapped() { onCropRequested?() }
    @objc private func saveTapped() { onSaveRequested?() }
    @objc private func quickSaveTapped() { onQuickSaveRequested?() }
    @objc private func copyTapped() { onCopyRequested?() }

    @objc private func resetTapped() {
        adjustments = ImageAdjustments()
        onAdjustmentsChanged?(adjustments)
    }
}
