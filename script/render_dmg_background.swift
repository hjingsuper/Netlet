import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dmg-background.png")
let canvas = NSSize(width: 720, height: 460)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width),
    pixelsHigh: Int(canvas.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
defer { NSGraphicsContext.restoreGraphicsState() }

let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.965, green: 0.98, blue: 1, alpha: 1),
    NSColor(calibratedRed: 0.91, green: 0.95, blue: 1, alpha: 1),
])!
background.draw(in: NSRect(origin: .zero, size: canvas), angle: 90)

func roundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

roundedRect(
    NSRect(x: 52, y: 174, width: 240, height: 172),
    radius: 86,
    color: NSColor(calibratedRed: 0.82, green: 0.90, blue: 1, alpha: 0.76)
)
roundedRect(
    NSRect(x: 428, y: 174, width: 240, height: 172),
    radius: 86,
    color: NSColor(calibratedRed: 0.82, green: 0.90, blue: 1, alpha: 0.76)
)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 320, y: 260))
arrow.line(to: NSPoint(x: 400, y: 260))
arrow.move(to: NSPoint(x: 373, y: 287))
arrow.line(to: NSPoint(x: 400, y: 260))
arrow.line(to: NSPoint(x: 373, y: 233))
arrow.lineWidth = 11
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.92, alpha: 0.86).setStroke()
arrow.stroke()

let centered = NSMutableParagraphStyle()
centered.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 26, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.11, blue: 0.22, alpha: 1),
    .paragraphStyle: centered,
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.31, green: 0.39, blue: 0.52, alpha: 1),
    .paragraphStyle: centered,
]
let brandAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.96, alpha: 1),
    .paragraphStyle: centered,
]

("NETLET" as NSString).draw(
    in: NSRect(x: 0, y: 402, width: canvas.width, height: 24),
    withAttributes: brandAttributes
)
("拖动 Netlet 到“应用程序”完成安装" as NSString).draw(
    in: NSRect(x: 0, y: 86, width: canvas.width, height: 38),
    withAttributes: titleAttributes
)
("Drag Netlet to Applications" as NSString).draw(
    in: NSRect(x: 0, y: 56, width: canvas.width, height: 24),
    withAttributes: subtitleAttributes
)

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render PNG")
}
try pngData.write(to: outputURL, options: .atomic)
