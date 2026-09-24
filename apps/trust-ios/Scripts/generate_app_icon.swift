import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let navy = CGColor(srgbRed: 0x14 / 255.0, green: 0x23 / 255.0, blue: 0x3B / 255.0, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

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

// Two overlapping circular rings form a simple connection mark.
func ring(center: CGPoint, radius: CGFloat) {
    let bounds = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    context.setStrokeColor(white)
    context.setLineWidth(58)
    context.strokeEllipse(in: bounds)
}

ring(center: CGPoint(x: 400, y: 512), radius: 205)
ring(center: CGPoint(x: 624, y: 512), radius: 205)

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
