import AppKit

struct OpticalProfile {
    let topBarWidth: CGFloat
    let topBarHeight: CGFloat
    let stemWidth: CGFloat
    let stemHeight: CGFloat
    let topBarCornerRadius: CGFloat
    let stemCornerRadius: CGFloat

    static func forCanvas(_ size: Int) -> OpticalProfile {
        switch size {
        case ..<32:
            return OpticalProfile(
                topBarWidth: 80,
                topBarHeight: 22,
                stemWidth: 36,
                stemHeight: 62,
                topBarCornerRadius: 0,
                stemCornerRadius: 0
            )
        case ..<64:
            return OpticalProfile(
                topBarWidth: 72,
                topBarHeight: 20,
                stemWidth: 32,
                stemHeight: 62,
                topBarCornerRadius: 0,
                stemCornerRadius: 0
            )
        case ..<128:
            return OpticalProfile(
                topBarWidth: 68,
                topBarHeight: 18,
                stemWidth: 28,
                stemHeight: 62,
                topBarCornerRadius: 1,
                stemCornerRadius: 1
            )
        case ..<256:
            return OpticalProfile(
                topBarWidth: 64,
                topBarHeight: 16,
                stemWidth: 24,
                stemHeight: 60,
                topBarCornerRadius: 1,
                stemCornerRadius: 1
            )
        default:
            return OpticalProfile(
                topBarWidth: 64,
                topBarHeight: 14,
                stemWidth: 20,
                stemHeight: 60,
                topBarCornerRadius: 2,
                stemCornerRadius: 3
            )
        }
    }
}

enum Theme {
    case light
    case dark

    var startColor: NSColor {
        switch self {
        case .light: return NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        case .dark: return NSColor(calibratedRed: 0.1725, green: 0.1725, blue: 0.1804, alpha: 1.0)
        }
    }

    var endColor: NSColor {
        switch self {
        case .light: return NSColor(calibratedRed: 0.898, green: 0.898, blue: 0.9176, alpha: 1.0)
        case .dark: return NSColor(calibratedRed: 0.1098, green: 0.1098, blue: 0.1176, alpha: 1.0)
        }
    }

    var glyphColor: NSColor {
        switch self {
        case .light: return NSColor(calibratedRed: 0.0392, green: 0.0392, blue: 0.0471, alpha: 1.0)
        case .dark: return NSColor(calibratedRed: 0.9608, green: 0.9608, blue: 0.9686, alpha: 1.0)
        }
    }
}

@discardableResult
func renderIcon(size: Int, theme: Theme, outputURL: URL) throws -> Bool {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    let squircleInset = CGFloat(size) * 0.033
    let iconRect = canvas.insetBy(dx: squircleInset, dy: squircleInset)
    let radius = iconRect.width * 0.185
    let squirclePath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    squirclePath.addClip()

    let gradient = NSGradient(starting: theme.startColor, ending: theme.endColor)!
    gradient.draw(in: squirclePath, angle: -90)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(theme == .light ? 0.12 : 0.36)
    shadow.shadowBlurRadius = CGFloat(size) * 0.045
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(size) * 0.01)
    shadow.set()

    let borderPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)
    theme.glyphColor.withAlphaComponent(theme == .light ? 0.05 : 0.10).setStroke()
    borderPath.lineWidth = max(1, CGFloat(size) * 0.004)
    borderPath.stroke()

    let profile = OpticalProfile.forCanvas(size)
    let scale = iconRect.width / 140.0

    let originX = iconRect.minX
    let originY = iconRect.minY

    func scaledRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: originX + x * scale,
            y: originY + y * scale,
            width: width * scale,
            height: height * scale
        )
    }

    let topBarX = 70.0 - (profile.topBarWidth / 2.0)
    let topBarRect = scaledRect(
        x: topBarX,
        y: 32,
        width: profile.topBarWidth,
        height: profile.topBarHeight
    )
    let stemX = 70.0 - (profile.stemWidth / 2.0)
    let stemRect = scaledRect(
        x: stemX,
        y: 58,
        width: profile.stemWidth,
        height: profile.stemHeight
    )

    theme.glyphColor.setFill()
    NSBezierPath(
        roundedRect: topBarRect,
        xRadius: profile.topBarCornerRadius * scale,
        yRadius: profile.topBarCornerRadius * scale
    ).fill()
    NSBezierPath(
        roundedRect: stemRect,
        xRadius: profile.stemCornerRadius * scale,
        yRadius: profile.stemCornerRadius * scale
    ).fill()

    guard
        let tiffData = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiffData),
        let pngData = rep.representation(using: .png, properties: [:])
    else {
        return false
    }

    try pngData.write(to: outputURL, options: .atomic)
    return true
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let appIconDir = root.appendingPathComponent("HideMyData/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let appLogoDir = root.appendingPathComponent("HideMyData/Assets.xcassets/AppLogo.imageset", isDirectory: true)

let outputs: [(String, Int, Theme)] = [
    ("icon_16.png", 16, .light),
    ("icon_16@2x.png", 32, .light),
    ("icon_32.png", 32, .light),
    ("icon_32@2x.png", 64, .light),
    ("icon_128.png", 128, .light),
    ("icon_128@2x.png", 256, .light),
    ("icon_256.png", 256, .light),
    ("icon_256@2x.png", 512, .light),
    ("icon_512.png", 512, .light),
    ("icon_512@2x.png", 1024, .light),
    ("icon_1024.png", 1024, .light),
    ("icon_1024_dark.png", 1024, .dark),
    ("logo.png", 1024, .light)
]

for (filename, size, theme) in outputs {
    let directory = filename == "logo.png" ? appLogoDir : appIconDir
    let outputURL = directory.appendingPathComponent(filename)
    try renderIcon(size: size, theme: theme, outputURL: outputURL)
    print("Wrote \(outputURL.path)")
}
