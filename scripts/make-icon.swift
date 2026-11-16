// Draws the Snapdeck app icon with CoreGraphics. No assets, no dependencies.
// Run scripts/make-icon.sh to rebuild Support/AppIcon.icns from it.
//
//   swift scripts/make-icon.swift <output.png> [size]
import AppKit

let canvas: CGFloat = 1024
/// The icon body follows the macOS grid: 824pt square on a 1024pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A rectangle given as fractions of `area`, measured from the top-left corner.
func pane(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in area: CGRect, gap: CGFloat) -> CGRect {
    CGRect(x: area.minX + x * area.width, y: area.maxY - (y + h) * area.height,
           width: w * area.width, height: h * area.height).insetBy(dx: gap / 2, dy: gap / 2)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func gradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func drawBody(_ ctx: CGContext, colors: [CGColor]) {
    // Soft shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.32))
    ctx.addPath(rounded(body, bodyRadius))
    ctx.setFillColor(colors[colors.count - 1])
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(rounded(body, bodyRadius))
    ctx.clip()
    gradient(ctx, colors, from: CGPoint(x: body.midX, y: body.maxY), to: CGPoint(x: body.midX, y: body.minY))
    // A faint highlight along the top edge.
    gradient(ctx, [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)],
             from: CGPoint(x: body.midX, y: body.maxY), to: CGPoint(x: body.midX, y: body.maxY - 260))
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, _ c: CGColor, shadow: Bool = true) {
    ctx.saveGState()
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x000000, 0.18)) }
    ctx.addPath(rounded(rect, radius))
    ctx.setFillColor(c)
    ctx.fillPath()
    ctx.restoreGState()
}

/// One main window with two stacked beside it (the "Main + Stack" layout),
/// on a gradient from moss green to British racing green.
func draw(in ctx: CGContext) {
    let area = body.insetBy(dx: 140, dy: 140)
    let gap: CGFloat = 34
    let radius: CGFloat = 44

    drawBody(ctx, colors: [color(0x7C9A4E), color(0x2E6B3A), color(0x0A3D24)])
    fill(ctx, pane(0, 0, 0.6, 1, in: area, gap: gap), radius: radius, color(0xFFFFFF))
    fill(ctx, pane(0.6, 0, 0.4, 0.5, in: area, gap: gap), radius: radius, color(0xFFFFFF, 0.72))
    fill(ctx, pane(0.6, 0.5, 0.4, 0.5, in: area, gap: gap), radius: radius, color(0xFFFFFF, 0.46))
}

func bitmap(width: Int, height: Int, _ body: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    body(ctx)
    return rep
}

func icon(size: Int) -> NSBitmapImageRep {
    bitmap(width: size, height: size) { ctx in
        ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
        draw(in: ctx)
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make-icon.swift <output.png> [size]")
    exit(1)
}
let rep = icon(size: args.count > 2 ? Int(args[2]) ?? 1024 : 1024)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
