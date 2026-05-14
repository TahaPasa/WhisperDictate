#!/usr/bin/env swift
// Generates Resources/AppIcon.icns for WhisperDictate.
// Called by build-app.sh.  Requires macOS 13+, Xcode CLT.
import AppKit
import Foundation

_ = NSApplication.shared  // required for AppKit symbol images in CLI

let scriptDir    = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot     = scriptDir.deletingLastPathComponent()
let resourcesDir = repoRoot.appendingPathComponent("Resources")
let iconsetDir   = resourcesDir.appendingPathComponent("AppIcon.iconset")
let icnsURL      = resourcesDir.appendingPathComponent("AppIcon.icns")

let fm = FileManager.default
try? fm.removeItem(at: iconsetDir)
do {
    try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
} catch {
    fputs("✗ failed to create \(iconsetDir.path): \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Draw a mic icon at the given pixel size using an explicit CGBitmapContext
// (NSImage.lockFocus is unreliable in headless CLI; this approach is guaranteed).
func renderIcon(pixel: Int) -> Data {
    let sz = CGFloat(pixel)

    // ── 1. Explicit CGBitmapContext ──────────────────────────────────────
    guard let ctx = CGContext(
        data: nil, width: pixel, height: pixel,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return Data() }

    // Wrap in NSGraphicsContext so AppKit drawing calls (NSBezierPath, NSColor) use it
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    defer { NSGraphicsContext.restoreGraphicsState() }

    // ── 2. Squircle clip + dark-blue gradient background ────────────────
    let cr   = sz * 0.225
    let bg   = NSBezierPath(roundedRect: NSRect(x:0, y:0, width:sz, height:sz),
                             xRadius:cr, yRadius:cr)
    bg.addClip()

    let cs   = CGColorSpaceCreateDeviceRGB()
    let topC = CGColor(red:0.13, green:0.22, blue:0.44, alpha:1)
    let botC = CGColor(red:0.05, green:0.08, blue:0.18, alpha:1)
    let grad = CGGradient(colorsSpace: cs, colors:[topC, botC] as CFArray, locations:[0,1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x:sz/2, y:sz),
                           end:   CGPoint(x:sz/2, y:0),
                           options: [])

    // ── 3. SF Symbol mic.fill — white palette ───────────────────────────
    let pt  = sz * 0.50
    let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let x = (sz - sym.size.width)  / 2
        let y = (sz - sym.size.height) / 2 + sz * 0.015
        sym.draw(in: NSRect(x:x, y:y, width:sym.size.width, height:sym.size.height),
                 from: .zero, operation: .sourceOver, fraction: 0.95)
    } else {
        // Fallback: hand-drawn mic shape if SF Symbol unavailable
        drawMic(ctx: ctx, sz: sz)
    }

    guard let cgImg = ctx.makeImage() else { return Data() }
    let bitmap = NSBitmapImageRep(cgImage: cgImg)
    return bitmap.representation(using: .png, properties: [:]) ?? Data()
}

// Fallback geometric mic using CoreGraphics bezier paths
func drawMic(ctx: CGContext, sz: CGFloat) {
    ctx.setFillColor(CGColor(red:1, green:1, blue:1, alpha:0.92))

    // Capsule body
    let bodyW = sz * 0.28, bodyH = sz * 0.42
    let bodyX = (sz - bodyW) / 2, bodyY = sz * 0.32
    let r = bodyW / 2
    let bodyPath = CGMutablePath()
    bodyPath.addRoundedRect(in: CGRect(x:bodyX, y:bodyY, width:bodyW, height:bodyH),
                             cornerWidth:r, cornerHeight:r)
    ctx.addPath(bodyPath); ctx.fillPath()

    // Pickup arch
    ctx.setLineWidth(sz * 0.04)
    ctx.setStrokeColor(CGColor(red:1, green:1, blue:1, alpha:0.92))
    let archCX = sz/2, archCY = sz * 0.50, archR = sz * 0.24
    ctx.addArc(center: CGPoint(x:archCX, y:archCY), radius:archR,
               startAngle: .pi, endAngle: 0, clockwise: true)
    ctx.strokePath()

    // Stand
    ctx.move(to:    CGPoint(x:sz/2, y:sz * 0.50 - archR))
    ctx.addLine(to: CGPoint(x:sz/2, y:sz * 0.18))
    ctx.strokePath()

    // Base
    let bw = sz * 0.30
    ctx.move(to:    CGPoint(x:sz/2 - bw/2, y:sz * 0.18))
    ctx.addLine(to: CGPoint(x:sz/2 + bw/2, y:sz * 0.18))
    ctx.setLineCap(.round)
    ctx.strokePath()
}

// ── Render all required icon sizes ─────────────────────────────────────────
let slots: [(String, Int)] = [
    ("icon_16x16",      16), ("icon_16x16@2x",    32),
    ("icon_32x32",      32), ("icon_32x32@2x",    64),
    ("icon_128x128",   128), ("icon_128x128@2x", 256),
    ("icon_256x256",   256), ("icon_256x256@2x", 512),
    ("icon_512x512",   512), ("icon_512x512@2x",1024),
]

print("Rendering icon sizes...")
for (name, px) in slots {
    let png = renderIcon(pixel: px)
    if png.isEmpty { fputs("⚠ \(name) failed\n", stderr); continue }
    do {
        try png.write(to: iconsetDir.appendingPathComponent("\(name).png"))
    } catch {
        fputs("✗ failed to write \(name).png: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    print("  ✓ \(name).png (\(px)px)")
}

let proc = Process()
proc.launchPath = "/usr/bin/iconutil"
proc.arguments  = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
do {
    try proc.run()
} catch {
    fputs("✗ could not launch iconutil: \(error.localizedDescription)\n", stderr)
    exit(1)
}
proc.waitUntilExit()

guard proc.terminationStatus == 0 else {
    fputs("iconutil failed (\(proc.terminationStatus))\n", stderr); exit(1)
}
try? fm.removeItem(at: iconsetDir)
print("✓ AppIcon.icns → \(icnsURL.path)")
