import Cocoa

/// Pixel-editing operations applied to a rectangular region of an NSImage.
/// All rects are expected in the image's own point coordinate space
/// (matching ImageCanvasView, whose frame size equals image.size).
enum ImageEffects {
    /// Returns just the processed patch, sized to the (clamped) rect — the
    /// caller draws it back into place. This must NOT return a full copy of
    /// `image` with the patch already composited in: RegionEffectAnnotation
    /// draws the result scaled into `rect`, so a full-size return value gets
    /// squeezed down and rendered as a shrunken duplicate of the whole
    /// screenshot inside the selection instead of just the mosaic/blur.
    static func mosaic(_ image: NSImage, in rect: NSRect, blockSize: CGFloat = 12) -> NSImage {
        guard let clamped = clampedRect(rect, to: image.size) else { return NSImage(size: rect.size) }

        let sub = cropped(image, to: clamped)
        let smallSize = NSSize(
            width: max(1, clamped.width / blockSize),
            height: max(1, clamped.height / blockSize)
        )

        let small = NSImage(size: smallSize)
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        sub.draw(in: NSRect(origin: .zero, size: smallSize),
                 from: NSRect(origin: .zero, size: sub.size),
                 operation: .copy, fraction: 1.0)
        small.unlockFocus()

        let patch = NSImage(size: clamped.size)
        patch.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        small.draw(in: NSRect(origin: .zero, size: clamped.size),
                   from: NSRect(origin: .zero, size: smallSize),
                   operation: .copy, fraction: 1.0)
        patch.unlockFocus()
        return patch
    }

    static func blur(_ image: NSImage, in rect: NSRect, radius: CGFloat = 10) -> NSImage {
        guard let clamped = clampedRect(rect, to: image.size) else { return NSImage(size: rect.size) }

        let sub = cropped(image, to: clamped)
        guard let tiff = sub.tiffRepresentation, let ciImage = CIImage(data: tiff) else { return sub }

        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
        blurFilter?.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = blurFilter?.outputImage?.cropped(to: ciImage.extent) else { return sub }
        let rep = NSCIImageRep(ciImage: output)
        let blurred = NSImage(size: rep.size)
        blurred.addRepresentation(rep)
        return blurred
    }

    private static func clampedRect(_ rect: NSRect, to size: NSSize) -> NSRect? {
        let bounds = NSRect(origin: .zero, size: size)
        let result = rect.intersection(bounds)
        guard result.width > 1, result.height > 1 else { return nil }
        return result
    }

    private static func cropped(_ image: NSImage, to rect: NSRect) -> NSImage {
        let result = NSImage(size: rect.size)
        result.lockFocus()
        image.draw(at: .zero, from: rect, operation: .copy, fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
