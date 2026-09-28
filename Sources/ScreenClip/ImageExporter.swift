import Cocoa
import UniformTypeIdentifiers

/// The formats offered in the save panel's format popup. Encoding settings
/// and the popup's contents both come from here so the two can't drift.
enum ExportFormat: String, CaseIterable {
    case png, jpeg, tiff, bmp, gif

    /// Every extension the picker recognizes as "ours" — used to tell an
    /// image extension apart from a dot that's just part of the file name
    /// (the generated names carry dots in the timestamp).
    static let knownExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "gif"]

    static func matching(extension ext: String) -> ExportFormat {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "tif", "tiff": return .tiff
        case "bmp": return .bmp
        case "gif": return .gif
        default: return .png
        }
    }

    var title: String {
        switch self {
        case .png: return "PNG (.png)"
        case .jpeg: return "JPEG (.jpg)"
        case .tiff: return "TIFF (.tiff)"
        case .bmp: return "BMP (.bmp)"
        case .gif: return "GIF (.gif)"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .bmp: return "bmp"
        case .gif: return "gif"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .bmp: return .bmp
        case .gif: return .gif
        }
    }

    var fileType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .bmp: return .bmp
        case .gif: return .gif
        }
    }

    var properties: [NSBitmapImageRep.PropertyKey: Any] {
        self == .jpeg ? [.compressionFactor: 0.9] : [:]
    }

    /// JPEG/BMP have no alpha channel — transparent pixels are composited
    /// onto white before encoding instead of coming out black.
    var supportsAlpha: Bool {
        self != .jpeg && self != .bmp
    }
}

enum ImageExporter {
    @discardableResult
    static func write(_ image: NSImage, to url: URL) -> Bool {
        write(image, to: url, format: .matching(extension: url.pathExtension))
    }

    @discardableResult
    static func write(_ image: NSImage, to url: URL, format: ExportFormat) -> Bool {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return false
        }

        let source = format.supportsAlpha ? bitmap : flattenedOnWhite(bitmap)
        guard let data = source.representation(using: format.fileType, properties: format.properties) else {
            return false
        }

        do {
            try data.write(to: url)
            return true
        } catch {
            NSLog("ScreenClip: failed to write image to \(url.path): \(error)")
            return false
        }
    }

    /// Redraws at the source's own pixel dimensions, so switching to a
    /// non-alpha format doesn't also cost resolution.
    private static func flattenedOnWhite(_ bitmap: NSBitmapImageRep) -> NSBitmapImageRep {
        guard bitmap.hasAlpha,
              let target = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: bitmap.pixelsWide,
                  pixelsHigh: bitmap.pixelsHigh,
                  bitsPerSample: 8,
                  samplesPerPixel: 3,
                  hasAlpha: false,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: target) else {
            return bitmap
        }

        let rect = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        rect.fill()
        bitmap.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        return target
    }
}
