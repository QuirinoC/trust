import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let paper = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let ink = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
let red = CGColor(srgbRed: 225 / 255, green: 6 / 255, blue: 0, alpha: 1)

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create context\n", stderr)
    exit(1)
}

context.setFillColor(paper)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
func ring(diameter: CGFloat, color: CGColor, width: CGFloat) {
    let rect = CGRect(
        x: center.x - diameter / 2,
        y: center.y - diameter / 2,
        width: diameter,
        height: diameter
    )
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokeEllipse(in: rect)
}

ring(diameter: CGFloat(size) * 0.62, color: ink, width: 6)
ring(diameter: CGFloat(size) * 0.46, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35), width: 8)
ring(diameter: CGFloat(size) * 0.30, color: red, width: 12)

let aperture = CGFloat(size) * 0.07
let apertureRect = CGRect(
    x: center.x + CGFloat(size) * 0.08 - aperture / 2,
    y: center.y + CGFloat(size) * 0.10 - aperture / 2,
    width: aperture,
    height: aperture
)
context.setFillColor(red)
context.fillEllipse(in: apertureRect)

guard let image = context.makeImage() else {
    fputs("Failed to make image\n", stderr)
    exit(1)
}

let destinationPath = CommandLine.arguments.dropFirst().first
    ?? "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
let url = URL(fileURLWithPath: destinationPath) as CFURL
guard let destination = CGImageDestinationCreateWithURL(
    url,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Failed to create PNG destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Failed to write PNG\n", stderr)
    exit(1)
}
print("Wrote \(destinationPath)")
