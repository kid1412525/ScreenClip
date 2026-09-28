import Cocoa

final class LabeledSlider: NSView {
    var onChanged: ((Double) -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let slider: NSSlider

    var value: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = newValue }
    }

    init(title: String, min: Double, max: Double) {
        slider = NSSlider(value: 0, minValue: min, maxValue: max, target: nil, action: nil)
        super.init(frame: .zero)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11)
        slider.target = self
        slider.action = #selector(sliderMoved)

        let stack = NSStackView(views: [titleLabel, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            slider.widthAnchor.constraint(equalToConstant: 180)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderMoved() {
        onChanged?(slider.doubleValue)
    }
}
