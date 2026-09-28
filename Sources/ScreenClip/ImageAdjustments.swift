import Cocoa

struct ImageAdjustments: Equatable {
    var brightness: Double = 0   // -1...1
    var contrast: Double = 1     // 0...4 (1 = no change)
    var saturation: Double = 1   // 0...2 (1 = no change)
    var hue: Double = 0          // radians, -pi...pi
    var sharpness: Double = 0    // 0...2
    var blur: Double = 0         // 0...20 (gaussian radius)
    var grayscale: Bool = false

    var isIdentity: Bool {
        self == ImageAdjustments()
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    func apply(to image: NSImage) -> NSImage {
        guard !isIdentity else { return image }
        guard let tiff = image.tiffRepresentation, var ciImage = CIImage(data: tiff) else { return image }
        let extent = ciImage.extent

        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(ciImage, forKey: kCIInputImageKey)
            colorControls.setValue(brightness, forKey: kCIInputBrightnessKey)
            colorControls.setValue(contrast, forKey: kCIInputContrastKey)
            colorControls.setValue(grayscale ? 0 : saturation, forKey: kCIInputSaturationKey)
            if let out = colorControls.outputImage { ciImage = out }
        }

        if hue != 0, let hueFilter = CIFilter(name: "CIHueAdjust") {
            hueFilter.setValue(ciImage, forKey: kCIInputImageKey)
            hueFilter.setValue(hue, forKey: kCIInputAngleKey)
            if let out = hueFilter.outputImage { ciImage = out }
        }

        if sharpness > 0, let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(ciImage, forKey: kCIInputImageKey)
            sharpen.setValue(sharpness, forKey: kCIInputSharpnessKey)
            if let out = sharpen.outputImage { ciImage = out }
        }

        if blur > 0, let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
            blurFilter.setValue(blur, forKey: kCIInputRadiusKey)
            if let out = blurFilter.outputImage?.cropped(to: extent) { ciImage = out }
        }

        guard let cgImage = Self.context.createCGImage(ciImage, from: extent) else { return image }
        return NSImage(cgImage: cgImage, size: image.size)
    }
}
