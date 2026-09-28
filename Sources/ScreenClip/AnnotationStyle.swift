import Cocoa

struct AnnotationStyle {
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat

    static let `default` = AnnotationStyle(color: .systemRed, lineWidth: 4, fontSize: 28)

    /// Offered by both the toolbar's size popup and the text dialog's.
    static let fontSizeChoices: [CGFloat] = [12, 16, 20, 24, 28, 36, 48, 64, 80]

    /// The list has no "custom" entry, so a size that came from somewhere
    /// else (an older annotation, a future preference) still lands on the
    /// nearest entry rather than leaving the popup showing the wrong value.
    static func nearestFontSizeIndex(to size: CGFloat) -> Int {
        let nearest = fontSizeChoices.enumerated().min { abs($0.element - size) < abs($1.element - size) }
        return nearest?.offset ?? 0
    }
}
