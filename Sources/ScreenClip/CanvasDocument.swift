import Cocoa

/// Holds one editor window's image state: the source pixels, non-destructive
/// color adjustments, and the vector annotations drawn on top. Rotate/flip/
/// resize/crop flatten annotations + adjustments into pixels first, which
/// keeps their transform math simple at the cost of those annotations no
/// longer being individually movable afterward (new annotations drawn after
/// stay fully editable).
final class CanvasDocument {
    private(set) var baseImage: NSImage
    private(set) var annotations: [Annotation] = []
    var adjustments = ImageAdjustments() {
        didSet {
            guard adjustments != oldValue else { return }
            adjustedCache = nil
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private var adjustedCache: NSImage?

    private struct Snapshot {
        let baseImage: NSImage
        let annotations: [Annotation]
        let adjustments: ImageAdjustments
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(image: NSImage) {
        self.baseImage = image
    }

    var adjustedBaseImage: NSImage {
        if let cached = adjustedCache { return cached }
        let result = adjustments.apply(to: baseImage)
        adjustedCache = result
        return result
    }

    var canvasSize: NSSize { baseImage.size }

    // MARK: - Undo/Redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func currentSnapshot() -> Snapshot {
        Snapshot(baseImage: baseImage, annotations: annotations.map { $0.clone() }, adjustments: adjustments)
    }

    /// Call once before an edit (or once before an interactive drag begins)
    /// so the pre-edit state becomes the undo point.
    func pushUndo() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations
        adjustedCache = nil
        adjustments = snapshot.adjustments
        onChange?()
    }

    // MARK: - Annotations

    func addAnnotation(_ annotation: Annotation) {
        pushUndo()
        annotations.append(annotation)
        onChange?()
    }

    func removeAnnotation(_ annotation: Annotation) {
        pushUndo()
        annotations.removeAll { $0 === annotation }
        onChange?()
    }

    func topmostAnnotation(at point: NSPoint) -> Annotation? {
        for annotation in annotations.reversed() where annotation.hitTest(point) {
            return annotation
        }
        return nil
    }

    func notifyChanged() {
        onChange?()
    }

    // MARK: - Geometric transforms

    private func flatten() -> NSImage {
        let source = adjustedBaseImage
        guard !annotations.isEmpty else { return source }
        let flattened = source.copy() as! NSImage
        flattened.lockFocus()
        for annotation in annotations {
            annotation.render(baseImage: source)
        }
        flattened.unlockFocus()
        return flattened
    }

    private func replaceFlattenedAndTransformed(_ transform: (NSImage) -> NSImage) {
        pushUndo()
        baseImage = transform(flatten())
        annotations = []
        adjustedCache = nil
        adjustments = ImageAdjustments()
        onChange?()
    }

    func rotate(clockwise: Bool) {
        replaceFlattenedAndTransformed { flattened in
            let newSize = NSSize(width: flattened.size.height, height: flattened.size.width)
            let result = NSImage(size: newSize)
            result.lockFocus()
            let transform = NSAffineTransform()
            if clockwise {
                transform.translateX(by: newSize.width, yBy: 0)
                transform.rotate(byDegrees: 90)
            } else {
                transform.translateX(by: 0, yBy: newSize.height)
                transform.rotate(byDegrees: -90)
            }
            transform.concat()
            flattened.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
            result.unlockFocus()
            return result
        }
    }

    func flip(horizontal: Bool) {
        replaceFlattenedAndTransformed { flattened in
            let size = flattened.size
            let result = NSImage(size: size)
            result.lockFocus()
            let transform = NSAffineTransform()
            if horizontal {
                transform.translateX(by: size.width, yBy: 0)
                transform.scaleX(by: -1, yBy: 1)
            } else {
                transform.translateX(by: 0, yBy: size.height)
                transform.scaleX(by: 1, yBy: -1)
            }
            transform.concat()
            flattened.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
            result.unlockFocus()
            return result
        }
    }

    func resize(to newSize: NSSize) {
        replaceFlattenedAndTransformed { flattened in
            let result = NSImage(size: newSize)
            result.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            flattened.draw(in: NSRect(origin: .zero, size: newSize),
                            from: NSRect(origin: .zero, size: flattened.size),
                            operation: .copy, fraction: 1.0)
            result.unlockFocus()
            return result
        }
    }

    func crop(to rect: NSRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        replaceFlattenedAndTransformed { flattened in
            let clamped = rect.intersection(NSRect(origin: .zero, size: flattened.size))
            let result = NSImage(size: clamped.size)
            result.lockFocus()
            flattened.draw(at: .zero, from: clamped, operation: .copy, fraction: 1.0)
            result.unlockFocus()
            return result
        }
    }

    func replaceImage(_ image: NSImage) {
        pushUndo()
        baseImage = image
        annotations = []
        adjustedCache = nil
        adjustments = ImageAdjustments()
        onChange?()
    }

    /// Flattened image (adjustments + annotations baked in), for copy/save.
    func flattenedForExport() -> NSImage {
        flatten()
    }
}
