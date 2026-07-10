// Renders the app icon at build time (no binary assets in the repo).
// Usage: swift Scripts/make-icon.swift <output.iconset directory>
// Best-effort: build.sh treats any failure here as "skip the icon".

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// Draws the icon into `rect` using only fractions of the size, so the same
/// code renders crisply at 16 px and 1024 px.
func drawIcon(in rect: NSRect) {
    let side = rect.width

    // Rounded-square background with a blue → violet wash.
    let inset = side * 0.055
    let backgroundRect = rect.insetBy(dx: inset, dy: inset)
    let background = NSBezierPath(roundedRect: backgroundRect, xRadius: side * 0.2, yRadius: side * 0.2)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.26, green: 0.42, blue: 0.96, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.52, green: 0.29, blue: 0.93, alpha: 1.0)
    )
    gradient?.draw(in: background, angle: -60)

    // White page.
    let pageWidth = side * 0.46
    let pageHeight = side * 0.60
    let pageRect = NSRect(
        x: rect.midX - pageWidth * 0.56,
        y: rect.midY - pageHeight * 0.52,
        width: pageWidth,
        height: pageHeight
    )
    let page = NSBezierPath(roundedRect: pageRect, xRadius: side * 0.03, yRadius: side * 0.03)
    NSColor.white.setFill()
    page.fill()

    // Faint text lines on the page.
    NSColor(calibratedWhite: 0.78, alpha: 1.0).setFill()
    let lineHeight = side * 0.028
    let lineInset = side * 0.05
    for lineIndex in 0..<4 {
        let width = pageRect.width - lineInset * 2 - (lineIndex == 3 ? pageRect.width * 0.3 : 0)
        let lineRect = NSRect(
            x: pageRect.minX + lineInset,
            y: pageRect.maxY - side * 0.14 - CGFloat(lineIndex) * lineHeight * 2.2,
            width: width,
            height: lineHeight
        )
        NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    }

    // Red "PDF" badge overlapping the page's lower left.
    let badgeWidth = side * 0.30
    let badgeHeight = side * 0.14
    let badgeRect = NSRect(
        x: pageRect.minX - side * 0.05,
        y: pageRect.minY + side * 0.05,
        width: badgeWidth,
        height: badgeHeight
    )
    let badge = NSBezierPath(roundedRect: badgeRect, xRadius: side * 0.03, yRadius: side * 0.03)
    NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.22, alpha: 1.0).setFill()
    badge.fill()

    let badgeFont = NSFont.systemFont(ofSize: badgeHeight * 0.62, weight: .heavy)
    let badgeText = NSAttributedString(string: "PDF", attributes: [
        .font: badgeFont,
        .foregroundColor: NSColor.white
    ])
    let textSize = badgeText.size()
    badgeText.draw(at: NSPoint(
        x: badgeRect.midX - textSize.width / 2,
        y: badgeRect.midY - textSize.height / 2
    ))

    // Sparkles by the page's top-right corner — the "it understands it" bit.
    NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.35, alpha: 1.0).setFill()
    drawSparkle(centerX: pageRect.maxX + side * 0.09, centerY: pageRect.maxY - side * 0.01, radius: side * 0.075)
    drawSparkle(centerX: pageRect.maxX + side * 0.16, centerY: pageRect.maxY - side * 0.12, radius: side * 0.042)
    drawSparkle(centerX: pageRect.maxX + side * 0.045, centerY: pageRect.maxY + side * 0.085, radius: side * 0.036)
}

/// Classic four-point sparkle: alternating long and short radii.
func drawSparkle(centerX: CGFloat, centerY: CGFloat, radius: CGFloat) {
    let path = NSBezierPath()
    let points = 8
    for index in 0..<points {
        let angle = (CGFloat(index) / CGFloat(points)) * 2 * .pi + .pi / 2
        let pointRadius = index % 2 == 0 ? radius : radius * 0.32
        let point = NSPoint(
            x: centerX + cos(angle) * pointRadius,
            y: centerY + sin(angle) * pointRadius
        )
        if index == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }
    path.close()
    path.fill()
}

func writePNG(pixelSize: Int, to url: URL) -> Bool {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return false }

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return false }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawIcon(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else { return false }
    do {
        try data.write(to: url)
        return true
    } catch {
        return false
    }
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for variant in variants {
    let url = outputDirectory.appendingPathComponent("\(variant.name).png")
    guard writePNG(pixelSize: variant.pixels, to: url) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
}
