// Generates the app icon (AppIcon.icns source PNG) and the template menu-bar icons
// from a black-on-transparent/white glyph PNG.
// Usage: swift tools/make-icons.swift <glyph.png> <output-dir>

import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3,
      let source = NSImage(contentsOfFile: args[1]),
      let glyph = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("usage: make-icons.swift <glyph.png> <output-dir>\n", stderr)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Alpha mask where dark glyph pixels are opaque, so it works whether the
/// source background is white or transparent.
func glyphMask(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    var rgba = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var mask = [UInt8](repeating: 255, count: w * h)
    for i in 0..<(w * h) {
        let a = Double(rgba[i * 4 + 3]) / 255
        guard a > 0 else { continue }
        let lum = (0.299 * Double(rgba[i * 4]) + 0.587 * Double(rgba[i * 4 + 1]) + 0.114 * Double(rgba[i * 4 + 2])) / 255 / a
        // CGImage masks paint where the sample is 0, so store the inverse of glyph coverage.
        mask[i] = 255 - UInt8(max(0, min(255, (1 - lum) * a * 255)))
    }
    let provider = CGDataProvider(data: Data(mask) as CFData)!
    return CGImage(maskWidth: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                   provider: provider, decode: nil, shouldInterpolate: true)!
}

func render(size: Int, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

let mask = glyphMask(glyph)

func fillGlyph(_ ctx: CGContext, in rect: CGRect, color: CGColor) {
    ctx.saveGState()
    ctx.clip(to: rect, mask: mask)
    ctx.setFillColor(color)
    ctx.fill(rect)
    ctx.restoreGState()
}

// Menu bar: black glyph on transparent, used as a template image (18pt @1x / @2x).
for (scale, suffix) in [(1, ""), (2, "@2x")] {
    let size = 18 * scale
    save(render(size: size) { ctx in
        fillGlyph(ctx, in: CGRect(x: 0, y: 0, width: size, height: size), color: .black)
    }, "MenuBarIcon\(suffix).png")
}

// App icon: Big Sur–style rounded tile (824/1024 with 100px margin) with a white glyph.
save(render(size: 1024) { ctx in
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.16, green: 0.42, blue: 0.36, alpha: 1),  // deep forest green
        CGColor(red: 0.30, green: 0.70, blue: 0.62, alpha: 1),  // misty teal
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()

    fillGlyph(ctx, in: CGRect(x: 192, y: 192, width: 640, height: 640), color: .white)
}, "AppIcon-1024.png")

print("icons written to \(outDir.path)")
