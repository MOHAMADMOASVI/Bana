#!/usr/bin/env swift
// Renders the AppIcon set: graphite squircle with a logo (or a green terminal prompt when none is given).
// Usage: swift Scripts/make-icon.swift <AppIcon.appiconset> [logo.png]
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let outDir = URL(fileURLWithPath: args.first ?? ".")
let logo: NSImage? = args.count > 1 ? NSImage(contentsOfFile: args[1]) : nil

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with a soft shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(red: 0.20, green: 0.22, blue: 0.26, alpha: 1).cgColor,
                                       NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Subtle top highlight.
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    ctx.setLineWidth(s * 0.006)
    ctx.addPath(path); ctx.strokePath()
    ctx.restoreGState()

    if let logo, let cg = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        // Fit the logo into 64% of the body height, centred, keeping its aspect ratio.
        let h = body.height * 0.64
        let w = h * CGFloat(cg.width) / CGFloat(cg.height)
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: body.midX - w / 2, y: body.midY - h / 2, width: w, height: h))
    } else {
        // Prompt: chevron + underscore, drawn as strokes so it stays crisp at 16px.
        let green = NSColor(red: 0.20, green: 0.84, blue: 0.42, alpha: 1).cgColor
        ctx.setStrokeColor(green)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setLineWidth(s * 0.075)
        let cx = body.minX + body.width * 0.30, cy = body.midY + body.height * 0.02, h = body.height * 0.17
        ctx.move(to: CGPoint(x: cx, y: cy + h))
        ctx.addLine(to: CGPoint(x: cx + h * 1.05, y: cy))
        ctx.addLine(to: CGPoint(x: cx, y: cy - h))
        ctx.strokePath()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.move(to: CGPoint(x: cx + h * 1.55, y: cy - h))
        ctx.addLine(to: CGPoint(x: cx + h * 2.65, y: cy - h))
        ctx.strokePath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try! render(pt * scale).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
    }
}
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outDir.path)")
