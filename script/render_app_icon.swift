import AppKit
import Foundation

let outputURL = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/AppIcon-1024.png"
)
let size = NSSize(width: 1024, height: 1024)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
defer { NSGraphicsContext.restoreGraphicsState() }

NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let tileRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 218, yRadius: 218)
NSColor(calibratedRed: 0.055, green: 0.42, blue: 0.96, alpha: 1).setFill()
tile.fill()

func drawArrow(x: CGFloat, startY: CGFloat, endY: CGFloat, pointsUp: Bool) {
    let path = NSBezierPath()
    path.lineWidth = 86
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    path.move(to: NSPoint(x: x, y: startY))
    path.line(to: NSPoint(x: x, y: endY))

    let headY = endY
    let wingY = pointsUp ? headY - 112 : headY + 112
    path.move(to: NSPoint(x: x - 105, y: wingY))
    path.line(to: NSPoint(x: x, y: headY))
    path.line(to: NSPoint(x: x + 105, y: wingY))

    NSColor.white.setStroke()
    path.stroke()
}

drawArrow(x: 365, startY: 700, endY: 330, pointsUp: false)
drawArrow(x: 659, startY: 324, endY: 694, pointsUp: true)

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon PNG")
}
try pngData.write(to: outputURL, options: .atomic)
