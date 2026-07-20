#!/usr/bin/env swift
//
//  generate-appicon.swift
//  RELL
//
//  Reproducible app-icon pipeline: renders the 1024×1024 master with
//  CoreGraphics (no external tools), then emits every mac-idiom size via
//  `sips`, and rewrites the appiconset's Contents.json.
//
//  Run from the repo root:
//      swift scripts/generate-appicon.swift
//
//  Design: text-free, macOS Big Sur grid (824pt squircle on a 1024 canvas),
//  an open book with a rising "lookup spark" — geometric shapes only so the
//  16px slot stays legible.
//

import AppKit
import CoreGraphics

// MARK: - Canvas

let canvas: CGFloat = 1024
guard let ctx = CGContext(
    data: nil, width: Int(canvas), height: Int(canvas),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("CGContext creation failed") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// MARK: - Background squircle (macOS grid: 824×824 centered, r≈186)

let plateRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let plate = CGPath(roundedRect: plateRect, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Rich blue-indigo vertical gradient — the app's "reading at dusk" identity.
ctx.saveGState()
ctx.addPath(plate)
ctx.clip()
let bgGradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [rgb(64, 120, 242), rgb(36, 62, 166)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: canvas / 2, y: plateRect.maxY),
    end: CGPoint(x: canvas / 2, y: plateRect.minY),
    options: []
)

// Subtle top-edge sheen for depth.
let sheen = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18),
             CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    sheen,
    start: CGPoint(x: canvas / 2, y: plateRect.maxY),
    end: CGPoint(x: canvas / 2, y: plateRect.maxY - 240),
    options: []
)
ctx.restoreGState()

// MARK: - Open book

// Geometry relative to the plate center. The book sits slightly below
// center; pages rise outward with gentle top curves.
let cx = canvas / 2
let bookBottom: CGFloat = 340
let bookTopOuter: CGFloat = 560     // outer page corners
let bookTopSpine: CGFloat = 500     // spine dip
let halfWidth: CGFloat = 250        // spine → outer edge
let pageCurve: CGFloat = 60         // top-edge curve depth

func pagePath(mirrored: Bool) -> CGMutablePath {
    // Right-hand page; mirrored=true flips across the spine.
    let sign: CGFloat = mirrored ? -1 : 1
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: bookBottom))                       // spine bottom
    p.addLine(to: CGPoint(x: cx + sign * halfWidth, y: bookBottom + 40))  // outer bottom
    p.addLine(to: CGPoint(x: cx + sign * halfWidth, y: bookTopOuter))     // outer top
    // Top edge curving down into the spine dip.
    p.addQuadCurve(
        to: CGPoint(x: cx, y: bookTopSpine),
        control: CGPoint(x: cx + sign * halfWidth * 0.45, y: bookTopOuter + pageCurve)
    )
    p.closeSubpath()
    return p
}

// Soft shadow under the book so it floats off the plate.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
ctx.addPath(pagePath(mirrored: true))
ctx.addPath(pagePath(mirrored: false))
ctx.setFillColor(rgb(246, 248, 252))
ctx.fillPath()
ctx.restoreGState()

// Slight tint on the left page so the spread reads as two pages at a glance.
ctx.addPath(pagePath(mirrored: true))
ctx.setFillColor(rgb(226, 232, 244))
ctx.fillPath()

// Spine line.
ctx.setStrokeColor(rgb(150, 165, 200))
ctx.setLineWidth(6)
ctx.move(to: CGPoint(x: cx, y: bookBottom + 8))
ctx.addLine(to: CGPoint(x: cx, y: bookTopSpine - 4))
ctx.strokePath()

// Text lines — three per page, following each page's slant.
ctx.setStrokeColor(rgb(160, 175, 210))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
for (i, y) in [400, 452, 504].enumerated() {
    let yF = CGFloat(y)
    let inset: CGFloat = 58
    let shorten: CGFloat = i == 2 ? 46 : 0   // top line shorter for rhythm
    // Right page
    ctx.move(to: CGPoint(x: cx + 44, y: yF + 10))
    ctx.addLine(to: CGPoint(x: cx + halfWidth - inset - shorten, y: yF + 26))
    // Left page
    ctx.move(to: CGPoint(x: cx - 44, y: yF + 10))
    ctx.addLine(to: CGPoint(x: cx - halfWidth + inset + shorten, y: yF + 26))
}
ctx.strokePath()

// MARK: - Lookup spark (the "language learner" mark)

// A four-point star floating above the spine dip — echoes the app's
// AI/lookup affordances. Warm gold so it reads against the blue.
func starPath(center: CGPoint, radius: CGFloat, waist: CGFloat) -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: center.x, y: center.y + radius))
    p.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y),
                   control: CGPoint(x: center.x + waist, y: center.y + waist))
    p.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius),
                   control: CGPoint(x: center.x + waist, y: center.y - waist))
    p.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y),
                   control: CGPoint(x: center.x - waist, y: center.y - waist))
    p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius),
                   control: CGPoint(x: center.x - waist, y: center.y + waist))
    p.closeSubpath()
    return p
}

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: rgb(255, 214, 120, 0.55))
ctx.addPath(starPath(center: CGPoint(x: cx, y: 668), radius: 74, waist: 20))
ctx.setFillColor(rgb(255, 205, 92))
ctx.fillPath()
// Small companion spark, offset — asymmetry keeps it lively.
ctx.addPath(starPath(center: CGPoint(x: cx + 122, y: 726), radius: 34, waist: 10))
ctx.setFillColor(rgb(255, 224, 150))
ctx.fillPath()
ctx.restoreGState()

// MARK: - Write master + sizes

guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
let rep = NSBitmapImageRep(cgImage: image)
guard let master = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}

let fm = FileManager.default
let assetDir = "Reader for Language Learner/Reader for Language Learner/Assets.xcassets/AppIcon.appiconset"
guard fm.fileExists(atPath: assetDir) else {
    fatalError("Run from the repo root — \(assetDir) not found")
}

let masterPath = assetDir + "/icon_512x512@2x.png"
try master.write(to: URL(fileURLWithPath: masterPath))
print("master 1024 written")

// filename → pixel size (the 1024 master doubles as 512@2x).
let slots: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
]
for (name, px) in slots {
    let out = assetDir + "/" + name
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(px)", "\(px)", masterPath, "--out", out]
    task.standardOutput = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("sips failed for \(name)") }
    print("\(name) (\(px)px) written")
}

// MARK: - Contents.json (clean 10-slot mac idiom set)

let contents = """
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(toFile: assetDir + "/Contents.json", atomically: true, encoding: .utf8)
print("Contents.json rewritten (mac idiom only)")
print("Done.")
