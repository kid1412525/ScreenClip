import Cocoa

/// A scroll view whose plain wheel/trackpad-scroll gesture zooms the
/// document instead of panning it, matching the "マウスホイール = 拡大縮小"
/// convention; panning is done explicitly via the hand tool or Space+drag.
/// Pinch-to-zoom keeps working automatically via NSScrollView's built-in
/// magnify(with:) handling.
final class ZoomScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = CenteringClipView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentView = CenteringClipView()
    }

    override func scrollWheel(with event: NSEvent) {
        guard allowsMagnification else {
            super.scrollWheel(with: event)
            return
        }
        guard event.deltaY != 0 else { return }

        let location = convert(event.locationInWindow, from: nil)
        let factor = 1 + (event.scrollingDeltaY * 0.01)
        let newMagnification = magnification * factor
        setMagnification(min(max(newMagnification, minMagnification), maxMagnification), centeredAt: location)
    }
}
