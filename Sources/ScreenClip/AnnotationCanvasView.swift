import Cocoa
import UniformTypeIdentifiers

final class AnnotationCanvasView: NSView {
    let document: CanvasDocument

    var tool: EditorTool = .select {
        didSet {
            guard tool != oldValue else { return }
            if tool != .select { selected = nil }
            if tool.isBoundsTool {
                cropRect = NSRect(origin: .zero, size: document.canvasSize)
            } else {
                cropRect = nil
            }
            boundsDraggingHandle = nil
            needsDisplay = true
        }
    }
    var style = AnnotationStyle.default

    var selected: Annotation? {
        didSet {
            needsDisplay = true
            onSelectionChanged?(selected)
        }
    }

    /// The crop/resize rect overlay — shown with drag handles for both
    /// .crop and .resize tools; Geometry.resized(handle:to:) drives it the
    /// same way an annotation's own resize handles work.
    var cropRect: NSRect? {
        didSet { needsDisplay = true }
    }

    var onDocumentChanged: (() -> Void)?
    var onToolChanged: ((EditorTool) -> Void)?
    var onSelectionChanged: ((Annotation?) -> Void)?
    var onTextInsertRequested: ((NSPoint) -> Void)?
    var onTextEditRequested: ((TextAnnotation) -> Void)?
    var onImageDropped: ((NSImage) -> Void)?
    var onCopied: (() -> Void)?

    private var pendingNewAnnotation: Annotation?
    private var pendingStart: NSPoint?
    private var draggingAnnotation: Annotation?
    private var draggingHandle: ResizeHandle?
    private var dragAnchor: NSPoint?
    private var hasPushedUndoForDrag = false
    private var boundsDraggingHandle: ResizeHandle?
    private var panAnchor: NSPoint?
    private var isSpaceDown = false

    init(document: CanvasDocument) {
        self.document = document
        super.init(frame: NSRect(origin: .zero, size: document.canvasSize))

        document.onChange = { [weak self] in
            guard let self else { return }
            let size = self.document.canvasSize
            if self.frame.size != size {
                self.frame = NSRect(origin: .zero, size: size)
            }
            self.needsDisplay = true
            self.onDocumentChanged?()
        }

        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        document.adjustedBaseImage.draw(in: bounds)

        for annotation in document.annotations {
            annotation.render(baseImage: document.adjustedBaseImage)
        }

        pendingNewAnnotation?.render(baseImage: document.adjustedBaseImage)

        if tool == .select, let selected {
            drawSelection(for: selected)
        }

        if tool.isBoundsTool, let cropRect {
            drawBoundsOverlay(cropRect)
        }
    }

    private func drawSelection(for annotation: Annotation) {
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: annotation.bounds)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()

        for handle in annotation.resizeHandles {
            let r = Geometry.handleRect(at: annotation.handlePosition(handle))
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: r).stroke()
        }
    }

    private func drawBoundsOverlay(_ rect: NSRect) {
        let outer = NSBezierPath(rect: bounds)
        outer.append(NSBezierPath(rect: rect))
        outer.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        outer.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()

        for handle in ResizeHandle.rectHandles {
            let r = Geometry.handleRect(at: Geometry.point(for: handle, in: rect))
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: r).stroke()
        }

        let sizeText = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        let textSize = (sizeText as NSString).size(withAttributes: attrs)
        let labelOrigin = NSPoint(x: rect.midX - textSize.width / 2, y: min(rect.maxY + 6, bounds.maxY - textSize.height))
        (sizeText as NSString).draw(at: labelOrigin, withAttributes: attrs)
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if isSpaceDown || tool == .pan {
            panAnchor = event.locationInWindow
            return
        }

        if event.clickCount == 2, tool == .select, let text = document.topmostAnnotation(at: point) as? TextAnnotation {
            onTextEditRequested?(text)
            return
        }

        switch tool {
        case .select:
            hasPushedUndoForDrag = false
            if let selected, let handle = handleHit(for: selected, at: point) {
                draggingHandle = handle
                draggingAnnotation = selected
                return
            }
            if let hit = document.topmostAnnotation(at: point) {
                selected = hit
                draggingAnnotation = hit
                dragAnchor = point
            } else {
                selected = nil
            }
        case .pan:
            break
        case .crop, .resize:
            if let cropRect, let handle = handleHit(onRect: cropRect, at: point) {
                boundsDraggingHandle = handle
            }
        case .pen, .marker:
            pendingNewAnnotation = FreehandAnnotation(points: [point], isMarker: tool == .marker, style: style)
        case .line, .arrow:
            pendingNewAnnotation = LineAnnotation(start: point, end: point, isArrow: tool == .arrow, style: style)
        case .rectangle:
            pendingStart = point
            pendingNewAnnotation = RectAnnotation(rect: NSRect(origin: point, size: .zero), style: style)
        case .ellipse:
            pendingStart = point
            pendingNewAnnotation = EllipseAnnotation(rect: NSRect(origin: point, size: .zero), style: style)
        case .mosaic:
            pendingStart = point
            pendingNewAnnotation = RegionEffectAnnotation(rect: NSRect(origin: point, size: .zero), effect: .mosaic)
        case .blur:
            pendingStart = point
            pendingNewAnnotation = RegionEffectAnnotation(rect: NSRect(origin: point, size: .zero), effect: .blur)
        case .text:
            onTextInsertRequested?(point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if isSpaceDown || tool == .pan {
            panBy(event: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)

        switch tool {
        case .select:
            guard draggingAnnotation != nil else { break }
            if !hasPushedUndoForDrag {
                document.pushUndo()
                hasPushedUndoForDrag = true
            }
            if let handle = draggingHandle, let annotation = draggingAnnotation {
                annotation.resize(handle: handle, to: point)
                document.notifyChanged()
            } else if let annotation = draggingAnnotation, let anchor = dragAnchor {
                annotation.moveBy(point.x - anchor.x, point.y - anchor.y)
                dragAnchor = point
                document.notifyChanged()
            }
        case .crop, .resize:
            guard let handle = boundsDraggingHandle, let rect = cropRect else { return }
            var newRect = Geometry.resized(rect, handle: handle, to: point)
            if tool == .crop {
                newRect = newRect.intersection(bounds)
            }
            if newRect.width >= 4, newRect.height >= 4 {
                cropRect = newRect
            }
        case .pen, .marker:
            (pendingNewAnnotation as? FreehandAnnotation)?.points.append(point)
            needsDisplay = true
        case .line, .arrow:
            (pendingNewAnnotation as? LineAnnotation)?.end = point
            needsDisplay = true
        case .rectangle, .ellipse, .mosaic, .blur:
            guard let start = pendingStart, let backed = pendingNewAnnotation as? RectBackedAnnotation else { return }
            backed.rect = rectBetween(start, point)
            needsDisplay = true
        case .pan, .text:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isSpaceDown || tool == .pan {
            panAnchor = nil
            return
        }

        defer { needsDisplay = true }

        switch tool {
        case .select:
            draggingAnnotation = nil
            draggingHandle = nil
            dragAnchor = nil
            hasPushedUndoForDrag = false
        case .crop, .resize:
            boundsDraggingHandle = nil
        case .pen, .marker, .line, .arrow, .rectangle, .ellipse, .mosaic, .blur:
            if let annotation = pendingNewAnnotation, max(annotation.bounds.width, annotation.bounds.height) > 2 {
                document.addAnnotation(annotation)
            }
            pendingNewAnnotation = nil
            pendingStart = nil
        case .pan, .text:
            break
        }
    }

    private func panBy(event: NSEvent) {
        guard let scrollView = enclosingScrollView else { return }
        if let anchor = panAnchor {
            let dx = event.locationInWindow.x - anchor.x
            let dy = event.locationInWindow.y - anchor.y
            var origin = scrollView.contentView.bounds.origin
            origin.x -= dx
            origin.y -= dy
            scrollView.contentView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        panAnchor = event.locationInWindow
    }

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func handleHit(for annotation: Annotation, at point: NSPoint) -> ResizeHandle? {
        for handle in annotation.resizeHandles {
            if Geometry.handleRect(at: annotation.handlePosition(handle)).insetBy(dx: -4, dy: -4).contains(point) {
                return handle
            }
        }
        return nil
    }

    private func handleHit(onRect rect: NSRect, at point: NSPoint) -> ResizeHandle? {
        for handle in ResizeHandle.rectHandles {
            if Geometry.handleRect(at: Geometry.point(for: handle, in: rect)).insetBy(dx: -4, dy: -4).contains(point) {
                return handle
            }
        }
        return nil
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // space
            isSpaceDown = true
            NSCursor.openHand.set()
            return
        }

        if tool.isBoundsTool {
            if event.keyCode == 36 { // Return
                if let cropRect {
                    if tool == .crop {
                        document.crop(to: cropRect)
                    } else {
                        document.resize(to: cropRect.size)
                    }
                }
                tool = .select
                onToolChanged?(.select)
                return
            }
            if event.keyCode == 53 { // Escape
                tool = .select
                onToolChanged?(.select)
                return
            }
        }

        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            if tool == .select, let selected {
                document.removeAnnotation(selected)
                self.selected = nil
            }
            return
        }

        if event.keyCode == 53 { // Escape
            selected = nil
            return
        }

        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           let newTool = EditorTool.allCases.first(where: { $0.shortcutKey == chars }) {
            tool = newTool
            onToolChanged?(newTool)
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceDown = false
            NSCursor.arrow.set()
            return
        }
        super.keyUp(with: event)
    }

    // MARK: - Standard editing actions
    //
    // Nil-targeted with standard NSResponder selector names, so Cmd+V/C/Z/⌫
    // route through the normal responder chain: a focused text field (e.g.
    // in a save/resize sheet) handles its own copy/paste/undo first, and
    // only falls through to these when the canvas itself has focus.

    @objc func paste(_ sender: Any?) {
        guard let image = NSImage(pasteboard: .general) else { return }
        document.replaceImage(image)
    }

    @objc func copy(_ sender: Any?) {
        PasteboardHelper.copy(image: document.flattenedForExport())
        onCopied?()
    }

    @objc func delete(_ sender: Any?) {
        guard tool == .select, let selected else { return }
        document.removeAnnotation(selected)
        self.selected = nil
    }

    @objc func undo(_ sender: Any?) { document.undo() }
    @objc func redo(_ sender: Any?) { document.redo() }

    // MARK: - Drag & drop import

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canReadImage(from: sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let image = readImage(from: sender) else { return false }
        onImageDropped?(image)
        return true
    }

    private func canReadImage(from sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(
            forClasses: [NSImage.self, NSURL.self],
            options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]
        )
    }

    private func readImage(from sender: NSDraggingInfo) -> NSImage? {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]
        ) as? [URL], let url = urls.first, let image = NSImage(contentsOf: url) {
            return image
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            return images.first
        }
        return nil
    }
}
