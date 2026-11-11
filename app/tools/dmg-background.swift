// Draws the DMG window background: app slot on the left, an arrow, Applications on the right.
// Usage: xcrun swift tools/dmg-background.swift <out.png> <scale 1|2>
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "background.png"
let scale = args.count > 2 ? CGFloat(Double(args[2]) ?? 1) : 1
let size = CGSize(width: 600, height: 380)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(srgbRed: 0.965, green: 0.965, blue: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// Arrow between the two icons (icons sit at x=160 and x=440, y=190 from the top).
let arrowY: CGFloat = size.height - 190
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 252, y: arrowY))
arrow.line(to: NSPoint(x: 342, y: arrowY))
arrow.move(to: NSPoint(x: 330, y: arrowY + 10))
arrow.line(to: NSPoint(x: 344, y: arrowY))
arrow.line(to: NSPoint(x: 330, y: arrowY - 10))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(white: 0.62, alpha: 1).setStroke()
arrow.stroke()

func draw(_ text: String, y: CGFloat, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    NSString(string: text).draw(in: NSRect(x: 0, y: y, width: size.width, height: fontSize * 1.5), withAttributes: attrs)
}

draw("Drag Skyward Plus to Applications", y: size.height - 62, size: 17, weight: .semibold, color: NSColor(white: 0.15, alpha: 1))
draw("First time on this Mac? Read “How to Open” below.", y: size.height - 86, size: 12, weight: .regular, color: NSColor(white: 0.42, alpha: 1))

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
