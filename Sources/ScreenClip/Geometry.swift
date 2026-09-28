import Cocoa

enum ResizeHandle: CaseIterable {
    case nw, n, ne, e, se, s, sw, w
    case start, end // for line/arrow endpoints

    static let rectHandles: [ResizeHandle] = [.nw, .n, .ne, .e, .se, .s, .sw, .w]
    static let lineHandles: [ResizeHandle] = [.start, .end]
}

enum Geometry {
    static let handleSize: CGFloat = 8
    static let hitTolerance: CGFloat = 6

    static func point(for handle: ResizeHandle, in rect: NSRect) -> NSPoint {
        switch handle {
        case .nw: return NSPoint(x: rect.minX, y: rect.maxY)
        case .n: return NSPoint(x: rect.midX, y: rect.maxY)
        case .ne: return NSPoint(x: rect.maxX, y: rect.maxY)
        case .e: return NSPoint(x: rect.maxX, y: rect.midY)
        case .se: return NSPoint(x: rect.maxX, y: rect.minY)
        case .s: return NSPoint(x: rect.midX, y: rect.minY)
        case .sw: return NSPoint(x: rect.minX, y: rect.minY)
        case .w: return NSPoint(x: rect.minX, y: rect.midY)
        case .start, .end: return .zero
        }
    }

    static func resized(_ rect: NSRect, handle: ResizeHandle, to point: NSPoint) -> NSRect {
        var r = rect
        switch handle {
        case .nw:
            r = NSRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: point.y - rect.minY)
        case .n:
            r = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: point.y - rect.minY)
        case .ne:
            r = NSRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: point.y - rect.minY)
        case .e:
            r = NSRect(x: rect.minX, y: rect.minY, width: point.x - rect.minX, height: rect.height)
        case .se:
            r = NSRect(x: rect.minX, y: point.y, width: point.x - rect.minX, height: rect.maxY - point.y)
        case .s:
            r = NSRect(x: rect.minX, y: point.y, width: rect.width, height: rect.maxY - point.y)
        case .sw:
            r = NSRect(x: point.x, y: point.y, width: rect.maxX - point.x, height: rect.maxY - point.y)
        case .w:
            r = NSRect(x: point.x, y: rect.minY, width: rect.maxX - point.x, height: rect.height)
        case .start, .end:
            return rect
        }
        return r.standardized
    }

    static func handleRect(at point: NSPoint) -> NSRect {
        NSRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2, width: handleSize, height: handleSize)
    }

    static func distance(from point: NSPoint, toSegment a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            return hypot(point.x - a.x, point.y - a.y)
        }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
