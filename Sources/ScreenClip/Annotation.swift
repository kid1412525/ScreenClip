import Cocoa

enum AnnotationKind {
    case pen, marker, line, arrow, rectangle, ellipse, text, mosaic, blur
}

protocol Annotation: AnyObject {
    var id: UUID { get }
    var kind: AnnotationKind { get }
    var bounds: NSRect { get }

    /// baseImage is the current adjusted (color-corrected) image, used as the
    /// live source for mosaic/blur so they always reflect the latest pixels.
    func render(baseImage: NSImage)
    func hitTest(_ point: NSPoint) -> Bool
    func moveBy(_ dx: CGFloat, _ dy: CGFloat)
    var resizeHandles: [ResizeHandle] { get }
    func handlePosition(_ handle: ResizeHandle) -> NSPoint
    func resize(handle: ResizeHandle, to point: NSPoint)
    func clone() -> Annotation

    /// nil for annotations with no color/thickness concept (mosaic, blur).
    var annotationStyle: AnnotationStyle? { get set }
}

/// Shared implementation for annotations whose geometry is a single rect
/// (rectangle, ellipse, mosaic, blur).
protocol RectBackedAnnotation: Annotation {
    var rect: NSRect { get set }
}

extension RectBackedAnnotation {
    var bounds: NSRect { rect }
    var resizeHandles: [ResizeHandle] { ResizeHandle.rectHandles }

    func hitTest(_ point: NSPoint) -> Bool {
        rect.insetBy(dx: -Geometry.hitTolerance, dy: -Geometry.hitTolerance).contains(point)
    }

    func moveBy(_ dx: CGFloat, _ dy: CGFloat) {
        rect = rect.offsetBy(dx: dx, dy: dy)
    }

    func handlePosition(_ handle: ResizeHandle) -> NSPoint {
        Geometry.point(for: handle, in: rect)
    }

    func resize(handle: ResizeHandle, to point: NSPoint) {
        rect = Geometry.resized(rect, handle: handle, to: point)
    }
}

/// Shared implementation for annotations that carry a color/thickness style
/// (everything except mosaic/blur).
protocol StyledAnnotation: Annotation {
    var style: AnnotationStyle { get set }
}

extension StyledAnnotation {
    var annotationStyle: AnnotationStyle? {
        get { style }
        set { if let newValue { style = newValue } }
    }
}

final class RectAnnotation: RectBackedAnnotation, StyledAnnotation {
    let id = UUID()
    let kind: AnnotationKind = .rectangle
    var rect: NSRect
    var style: AnnotationStyle

    init(rect: NSRect, style: AnnotationStyle) {
        self.rect = rect
        self.style = style
    }

    func render(baseImage: NSImage) {
        let path = NSBezierPath(rect: rect.standardized)
        path.lineWidth = style.lineWidth
        style.color.setStroke()
        path.stroke()
    }

    func clone() -> Annotation { RectAnnotation(rect: rect, style: style) }
}

final class EllipseAnnotation: RectBackedAnnotation, StyledAnnotation {
    let id = UUID()
    let kind: AnnotationKind = .ellipse
    var rect: NSRect
    var style: AnnotationStyle

    init(rect: NSRect, style: AnnotationStyle) {
        self.rect = rect
        self.style = style
    }

    func render(baseImage: NSImage) {
        let path = NSBezierPath(ovalIn: rect.standardized)
        path.lineWidth = style.lineWidth
        style.color.setStroke()
        path.stroke()
    }

    func clone() -> Annotation { EllipseAnnotation(rect: rect, style: style) }
}

final class RegionEffectAnnotation: RectBackedAnnotation {
    enum Effect { case mosaic, blur }

    let id = UUID()
    let effect: Effect
    var kind: AnnotationKind { effect == .mosaic ? .mosaic : .blur }
    var rect: NSRect

    init(rect: NSRect, effect: Effect) {
        self.rect = rect
        self.effect = effect
    }

    func render(baseImage: NSImage) {
        let patch = effect == .mosaic
            ? ImageEffects.mosaic(baseImage, in: rect.standardized)
            : ImageEffects.blur(baseImage, in: rect.standardized)
        patch.draw(in: rect.standardized, from: NSRect(origin: .zero, size: patch.size), operation: .copy, fraction: 1.0)
    }

    var annotationStyle: AnnotationStyle? {
        get { nil }
        set {}
    }

    func clone() -> Annotation { RegionEffectAnnotation(rect: rect, effect: effect) }
}

final class LineAnnotation: StyledAnnotation {
    let id = UUID()
    let isArrow: Bool
    var kind: AnnotationKind { isArrow ? .arrow : .line }
    var start: NSPoint
    var end: NSPoint
    var style: AnnotationStyle

    init(start: NSPoint, end: NSPoint, isArrow: Bool, style: AnnotationStyle) {
        self.start = start
        self.end = end
        self.isArrow = isArrow
        self.style = style
    }

    var bounds: NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            .insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
    }

    func render(baseImage: NSImage) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        style.color.setStroke()
        path.stroke()

        if isArrow {
            let headLength: CGFloat = max(12, style.lineWidth * 3.5)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let spread: CGFloat = .pi / 7
            let p1 = NSPoint(x: end.x - headLength * cos(angle - spread), y: end.y - headLength * sin(angle - spread))
            let p2 = NSPoint(x: end.x - headLength * cos(angle + spread), y: end.y - headLength * sin(angle + spread))
            let head = NSBezierPath()
            head.move(to: end)
            head.line(to: p1)
            head.line(to: p2)
            head.close()
            style.color.setFill()
            head.fill()
        }
    }

    func hitTest(_ point: NSPoint) -> Bool {
        Geometry.distance(from: point, toSegment: start, end) <= max(Geometry.hitTolerance, style.lineWidth)
    }

    func moveBy(_ dx: CGFloat, _ dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
    }

    var resizeHandles: [ResizeHandle] { ResizeHandle.lineHandles }

    func handlePosition(_ handle: ResizeHandle) -> NSPoint {
        handle == .start ? start : end
    }

    func resize(handle: ResizeHandle, to point: NSPoint) {
        if handle == .start { start = point } else if handle == .end { end = point }
    }

    func clone() -> Annotation { LineAnnotation(start: start, end: end, isArrow: isArrow, style: style) }
}

final class FreehandAnnotation: StyledAnnotation {
    let id = UUID()
    let isMarker: Bool
    var kind: AnnotationKind { isMarker ? .marker : .pen }
    var points: [NSPoint]
    var style: AnnotationStyle

    init(points: [NSPoint], isMarker: Bool, style: AnnotationStyle) {
        self.points = points
        self.isMarker = isMarker
        self.style = style
    }

    var bounds: NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let width = isMarker ? style.lineWidth * 3 : style.lineWidth
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -width, dy: -width)
    }

    func render(baseImage: NSImage) {
        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if isMarker {
            path.lineWidth = style.lineWidth * 3
            style.color.withAlphaComponent(0.35).setStroke()
        } else {
            path.lineWidth = style.lineWidth
            style.color.setStroke()
        }
        path.stroke()
    }

    func hitTest(_ point: NSPoint) -> Bool {
        guard points.count > 1 else { return false }
        let tolerance = max(Geometry.hitTolerance, isMarker ? style.lineWidth * 1.5 : style.lineWidth)
        for i in 0..<(points.count - 1) {
            if Geometry.distance(from: point, toSegment: points[i], points[i + 1]) <= tolerance {
                return true
            }
        }
        return false
    }

    func moveBy(_ dx: CGFloat, _ dy: CGFloat) {
        points = points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    var resizeHandles: [ResizeHandle] { [] }
    func handlePosition(_ handle: ResizeHandle) -> NSPoint { .zero }
    func resize(handle: ResizeHandle, to point: NSPoint) {}

    func clone() -> Annotation { FreehandAnnotation(points: points, isMarker: isMarker, style: style) }
}

final class TextAnnotation: StyledAnnotation {
    let id = UUID()
    let kind: AnnotationKind = .text
    var origin: NSPoint
    var text: String
    var style: AnnotationStyle

    init(origin: NSPoint, text: String, style: AnnotationStyle) {
        self.origin = origin
        self.text = text
        self.style = style
    }

    private var attributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.boldSystemFont(ofSize: style.fontSize),
            .foregroundColor: style.color,
            .strokeColor: NSColor.black,
            .strokeWidth: -2.0
        ]
    }

    var bounds: NSRect {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSRect(origin: origin, size: size).insetBy(dx: -4, dy: -4)
    }

    func render(baseImage: NSImage) {
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    func hitTest(_ point: NSPoint) -> Bool {
        bounds.contains(point)
    }

    func moveBy(_ dx: CGFloat, _ dy: CGFloat) {
        origin.x += dx; origin.y += dy
    }

    var resizeHandles: [ResizeHandle] { [] }
    func handlePosition(_ handle: ResizeHandle) -> NSPoint { .zero }
    func resize(handle: ResizeHandle, to point: NSPoint) {}

    func clone() -> Annotation { TextAnnotation(origin: origin, text: text, style: style) }
}
