import Cocoa

/// NSClipView centers its document view when the document is smaller than
/// the visible area, instead of leaving it pinned to the bottom-left —
/// used for the main canvas so a small screenshot doesn't look stranded in
/// a corner of a larger window.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame = documentView.frame
        if docFrame.width < rect.width {
            rect.origin.x = floor((docFrame.width - rect.width) / 2)
        }
        if docFrame.height < rect.height {
            rect.origin.y = floor((docFrame.height - rect.height) / 2)
        }
        return rect
    }
}

/// NSClipView pins its document view's top edge to the visible area's top
/// when the document is shorter than the visible area, instead of leaving
/// AppKit's default (effectively arbitrary) scroll position — used for the
/// left toolbar and right adjustments panel so their controls always start
/// flush against the top of the window.
final class TopAligningClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        // NSClipView is flipped (y = 0 at its own top), and the document
        // view's frame is top-pinned within it, so its content starts at
        // y = 0 in this same flipped space — that's the coordinate to pin
        // to, not docHeight - rect.height (which would be correct in a
        // non-flipped space, and was showing the bottom instead).
        if documentView.frame.height < rect.height {
            rect.origin.y = 0
        }
        return rect
    }
}
