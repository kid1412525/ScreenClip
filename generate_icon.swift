// One-off icon generator: draws a 1024x1024 app icon (gradient rounded
// square + viewfinder corner brackets + a shutter dot) and saves it as PNG.
// Run with: swift generate_icon.swift AppIcon-1024.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = 224
let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
background.addClip()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.30, green: 0.46, blue: 0.98, alpha: 1.0),
    NSColor(calibratedRed: 0.56, green: 0.24, blue: 0.90, alpha: 1.0)
])
gradient?.draw(in: background, angle: -45)

let inset: CGFloat = 236
let armLength: CGFloat = 168
let strokeWidth: CGFloat = 48
let corners: [(NSPoint, CGFloat, CGFloat)] = [
    (NSPoint(x: inset, y: size - inset), 1, -1),
    (NSPoint(x: size - inset, y: size - inset), -1, -1),
    (NSPoint(x: inset, y: inset), 1, 1),
    (NSPoint(x: size - inset, y: inset), -1, 1)
]

NSColor.white.setStroke()
for (corner, dx, dy) in corners {
    let bracket = NSBezierPath()
    bracket.lineWidth = strokeWidth
    bracket.lineCapStyle = .round
    bracket.lineJoinStyle = .round
    bracket.move(to: NSPoint(x: corner.x + armLength * dx, y: corner.y))
    bracket.line(to: corner)
    bracket.line(to: NSPoint(x: corner.x, y: corner.y + armLength * dy))
    bracket.stroke()
}

let dotRadius: CGFloat = 96
let dotRect = NSRect(x: size / 2 - dotRadius, y: size / 2 - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
NSColor.white.setFill()
NSBezierPath(ovalIn: dotRect).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render icon")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
