import AppKit
import Foundation

struct IconSpec {
    var name: String
    var hex1: UInt32
    var hex2: UInt32
}

let specs: [IconSpec] = [
    IconSpec(name: "AppIcon", hex1: 0x2F80ED, hex2: 0x56CCF2),
    IconSpec(name: "AppIconIndigo", hex1: 0x4F46E5, hex2: 0x818CF8),
    IconSpec(name: "AppIconForest", hex1: 0x1F9D55, hex2: 0x6FCF97),
    IconSpec(name: "AppIconSunset", hex1: 0xF2711C, hex2: 0xFFB347),
    IconSpec(name: "AppIconGraphite", hex1: 0x5B6472, hex2: 0x9AA5B1),
]

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func renderIcon(spec: IconSpec, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    let inset = size * 0.06
    let corner = size * 0.22
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: corner, yRadius: corner)
    NSGradient(starting: color(spec.hex1), ending: color(spec.hex2))?.draw(in: bgPath, angle: -45)

    // Subtle inner highlight border
    NSColor.white.withAlphaComponent(0.22).setStroke()
    bgPath.lineWidth = max(1, size * 0.015)
    bgPath.stroke()

    if let symbol = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .bold)
            .applying(.init(paletteColors: [.white]))
        if let configured = symbol.withSymbolConfiguration(cfg) {
            let symSize = configured.size
            let dst = NSRect(
                x: (size - symSize.width) / 2,
                y: (size - symSize.height) / 2,
                width: symSize.width,
                height: symSize.height
            )
            configured.draw(in: dst)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let assetsDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SkywardPlus/Resources/Assets.xcassets")
try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try rootContents.write(to: assetsDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let accentDir = assetsDir.appendingPathComponent("AccentColor.colorset")
try fm.createDirectory(at: accentDir, withIntermediateDirectories: true)
let accentJSON = """
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.929",
          "green" : "0.502",
          "red" : "0.184"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try accentJSON.write(to: accentDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let macSizes: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for spec in specs {
    let setDir = assetsDir.appendingPathComponent("\(spec.name).appiconset")
    try fm.createDirectory(at: setDir, withIntermediateDirectories: true)

    var imageEntries: [String] = []
    var writtenFiles = Set<String>()

    let iosFile = "icon-1024.png"
    if let data = renderIcon(spec: spec, pixels: 1024) {
        try data.write(to: setDir.appendingPathComponent(iosFile))
        writtenFiles.insert(iosFile)
    }
    imageEntries.append("""
        {
          "filename" : "\(iosFile)",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
    """)

    for item in macSizes {
        let px = item.pt * item.scale
        let filename = "icon-\(px).png"
        if !writtenFiles.contains(filename), let data = renderIcon(spec: spec, pixels: px) {
            try data.write(to: setDir.appendingPathComponent(filename))
            writtenFiles.insert(filename)
        }
        imageEntries.append("""
            {
              "filename" : "\(filename)",
              "idiom" : "mac",
              "scale" : "\(item.scale)x",
              "size" : "\(item.pt)x\(item.pt)"
            }
        """)
    }

    let contents = """
    {
      "images" : [
    \(imageEntries.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try contents.write(to: setDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("Generated Assets.xcassets in \(assetsDir.path)")
