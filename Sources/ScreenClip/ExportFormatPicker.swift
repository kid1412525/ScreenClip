import Cocoa

/// The save panel's accessory view: a format popup that rewrites the panel's
/// allowed type and the name field's extension as it changes, so the file
/// type can be picked in the dialog instead of by typing an extension.
final class ExportFormatPicker: NSView {
    var onFormatChanged: ((ExportFormat) -> Void)?

    private let popup = NSPopUpButton()
    private let formats = ExportFormat.allCases

    var format: ExportFormat {
        get { formats[max(popup.indexOfSelectedItem, 0)] }
        set {
            if let index = formats.firstIndex(of: newValue) {
                popup.selectItem(at: index)
            }
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 42))

        let label = NSTextField(labelWithString: "ファイル形式:")
        popup.addItems(withTitles: formats.map(\.title))
        popup.target = self
        popup.action = #selector(formatChanged)

        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func formatChanged() {
        onFormatChanged?(format)
    }
}
