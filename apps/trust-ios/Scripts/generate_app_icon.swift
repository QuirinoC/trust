import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let navy = CGColor(srgbRed: 0x14 / 255.0, green: 0x23 / 255.0, blue: 0x3B / 255.0, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let blue = CGColor(srgbRed: 0x6F / 255.0, green: 0x95 / 255.0, blue: 1, alpha: 1)
let teal = CGColor(srgbRed: 0x51 / 255.0, green: 0xC8 / 255.0, blue: 0xB3 / 255.0, alpha: 1)

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

context.setFillColor(navy)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Three open companion paths echo the sign-in artwork. The silhouette is
// intentionally asymmetrical and has no closed circles or infinity loop.
func stroke(_ color: CGColor, width: CGFloat, draw: () -> Void) {
    context.beginPath()
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    draw()
    context.strokePath()
}

stroke(white, width: 84) {
    context.move(to: CGPoint(x: 176, y: 246))
    context.addCurve(to: CGPoint(x: 710, y: 820),
                     control1: CGPoint(x: 286, y: 510),
                     control2: CGPoint(x: 466, y: 764))
}

stroke(blue, width: 84) {
    context.move(to: CGPoint(x: 348, y: 194))
    context.addCurve(to: CGPoint(x: 856, y: 686),
                     control1: CGPoint(x: 444, y: 422),
                     control2: CGPoint(x: 664, y: 642))
}

stroke(teal, width: 62) {
    context.move(to: CGPoint(x: 572, y: 214))
    context.addQuadCurve(to: CGPoint(x: 834, y: 430),
                         control: CGPoint(x: 676, y: 420))
}

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
