// Renders the app icon as a 1024x1024 PNG: swift make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let navy = NSColor(red: 0.04, green: 0.08, blue: 0.16, alpha: 1)
let blue = NSColor(red: 0.04, green: 0.20, blue: 0.32, alpha: 1)
let gold = NSColor(red: 0.78, green: 0.67, blue: 0.43, alpha: 1)
let lightGold = NSColor(red: 0.94, green: 0.86, blue: 0.62, alpha: 1)

func symbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
}

func drawCentered(_ image: NSImage, at center: CGPoint) {
    let s = image.size
    image.draw(in: CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt tile centered in a 1024pt canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
navy.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(starting: blue, ending: navy)!.draw(in: tilePath, angle: -90)

gold.setStroke()
let border = NSBezierPath(roundedRect: tile.insetBy(dx: 18, dy: 18), xRadius: 168, yRadius: 168)
border.lineWidth = 12
border.stroke()

drawCentered(symbol("gamecontroller.fill", pointSize: 330, color: lightGold), at: CGPoint(x: 512, y: 540))

// Lock badge, bottom right.
let badgeCenter = CGPoint(x: 735, y: 300)
let badge = NSBezierPath(ovalIn: CGRect(x: badgeCenter.x - 125, y: badgeCenter.y - 125, width: 250, height: 250))
gold.setFill()
badge.fill()
navy.setStroke()
badge.lineWidth = 16
badge.stroke()
drawCentered(symbol("lock.fill", pointSize: 120, color: navy), at: badgeCenter)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
