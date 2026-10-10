#!/usr/bin/env swift
//
//  generate-appicon.swift
//  RELL
//
//  Reproducible app-icon pipeline: splits the brand logo (docs/brand/rell-logo.svg)
//  into the layers of an Icon Composer document (AppIcon.icon), so macOS can
//  render every icon style itself — Default, Dark, Clear and Tinted, with
//  Liquid Glass. Xcode also derives the legacy AppIcon.icns (macOS 15) from it.
//  No external tools beyond Xcode's own ictool, used only for the preview PNG.
//
//  Run from the repo root:
//      swift scripts/generate-appicon.swift
//
//  Layers, front to back:
//    Bubbles  the A / 文 balloons (glyphs turn light in Dark, or they vanish on navy)
//    Ribbon   the teal front of the R, then its orange back face and leg
//    Book     the open book under the bowl
//  Fill: white → mint; in Dark the neutral graphite of Apple's own dark icons.
//
//  The .icon can be fine-tuned in Icon Composer afterwards; rerunning this
//  script overwrites those edits.
//

import AppKit
import Foundation

let fm = FileManager.default
let logoPath = "docs/brand/rell-logo.svg"
let iconDir = "Reader for Language Learner/Reader for Language Learner/AppIcon.icon"
let previewPath = "docs/brand/rell-icon-1024.png"
guard fm.fileExists(atPath: logoPath), fm.fileExists(atPath: "Reader for Language Learner/Reader for Language Learner") else {
    fatalError("Run from the repo root — \(logoPath) not found")
}
guard let logo = try? String(contentsOfFile: logoPath, encoding: .utf8) else { fatalError("\(logoPath) unreadable") }

// MARK: - Pull the pieces out of the logo

func matches(_ pattern: String, in text: String) -> [String] {
    let re = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
        String(text[Range($0.range, in: text)!])
    }
}

func gradient(_ id: String) -> String {
    guard let g = matches(#"<linearGradient id="\#(id)".*?</linearGradient>"#, in: logo).first else {
        fatalError("gradient \(id) missing from \(logoPath)")
    }
    return g
}

let paths = matches(#"<path [^>]*?/>"#, in: logo)
func path(_ marker: String) -> String {
    let hits = paths.filter { $0.contains(marker) }
    guard hits.count == 1 else { fatalError("expected one path with \(marker) in \(logoPath), found \(hits.count)") }
    return hits[0]
}
guard let glyphZh = matches(##"<g stroke="#125372".*?</g>"##, in: logo).first else { fatalError("文 glyph group missing") }

// MARK: - Glyph outlines
//
// The A / 文 glyphs are strokes in the logo. A layer fill (how Dark recolours them)
// paints a path's interior too, so an open stroke like the A's legs turns into a
// solid triangle. Outlining the strokes into filled shapes keeps them glyphs in
// every style. Handles the absolute M/L/H/V/C commands the glyphs use.

func cgPath(fromSVG d: String) -> CGPath {
    let tokens = matches(#"[MLHVCZmlhvcz]|-?\d*\.?\d+"#, in: d)
    let p = CGMutablePath()
    var i = 0, cmd = "M", cur = CGPoint.zero
    func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    while i < tokens.count {
        if tokens[i].first!.isLetter { cmd = tokens[i]; i += 1 }
        switch cmd {
        case "M": cur = CGPoint(x: num(), y: num()); p.move(to: cur); cmd = "L"
        case "L": cur = CGPoint(x: num(), y: num()); p.addLine(to: cur)
        case "H": cur.x = num(); p.addLine(to: cur)
        case "V": cur.y = num(); p.addLine(to: cur)
        case "C":
            let c1 = CGPoint(x: num(), y: num()), c2 = CGPoint(x: num(), y: num())
            cur = CGPoint(x: num(), y: num()); p.addCurve(to: cur, control1: c1, control2: c2)
        case "Z", "z": p.closeSubpath()
        default: fatalError("glyph path uses unsupported SVG command \(cmd)")
        }
    }
    return p
}

func svgD(_ path: CGPath) -> String {
    var d = ""
    func f(_ p: CGPoint) -> String { String(format: "%.2f %.2f", p.x, p.y) }
    path.applyWithBlock { el in
        let pts = el.pointee.points
        switch el.pointee.type {
        case .moveToPoint: d += "M\(f(pts[0]))"
        case .addLineToPoint: d += "L\(f(pts[0]))"
        case .addQuadCurveToPoint: d += "Q\(f(pts[0])) \(f(pts[1]))"
        case .addCurveToPoint: d += "C\(f(pts[0])) \(f(pts[1])) \(f(pts[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func outlinedGlyph(_ element: String) -> String {
    // every d="…" in the element, stroked at the logo's width with round caps and joins
    matches(#"d="[^"]+""#, in: element).map { attr in
        let d = String(attr.dropFirst(3).dropLast())
        let outline = cgPath(fromSVG: d).copy(strokingWithWidth: 10, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return ##"<path d="\##(svgD(outline))" fill="#125372"/>"##
    }.joined(separator: "\n    ")
}

// MARK: - Layer SVGs (1024 pt Icon Composer canvas)

// Artwork bbox (110,21)–(674,678) in logo units → 640 pt tall, centred
let scale = 640.0 / 657.0
let tx = 512 - 392 * scale, ty = 512 - 349.5 * scale

func layerSVG(_ items: [String], gradients: [String]) -> String {
    let body = items.joined(separator: "\n    ")
    let defs = gradients.map(gradient).joined(separator: "\n    ")
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" fill="none">
      <defs>
        \(defs)
      </defs>
      <g transform="translate(\(String(format: "%.2f %.2f", tx, ty))) scale(\(String(format: "%.5f", scale)))">
        \(body)
      </g>
    </svg>

    """
}

let layers: [(String, String)] = [
    // Glyphs get a layer of their own so Dark can recolour them with a layer fill:
    // actool drops image-name-specializations, so a separate dark SVG never ships.
    ("glyphs.svg", layerSVG([outlinedGlyph(path(##"stroke="#125372" stroke-width="10""##)), outlinedGlyph(glyphZh)],
                            gradients: [])),
    ("bubbles.svg", layerSVG([path("url(#tealBubble)"), path("url(#goldBubble)")], gradients: ["tealBubble", "goldBubble"])),
    ("ribbon-front.svg", layerSVG([path("url(#upperRibbon)"), path("url(#upperInset)"),
                                   path("url(#frontBowl)"), path("url(#innerBowl)")],
                                  gradients: ["upperRibbon", "upperInset", "frontBowl", "innerBowl"])),
    ("ribbon-back.svg", layerSVG([path("url(#rearBowl)"), path("url(#leg)"), path("url(#legFold)"), path("url(#stem)")],
                                 gradients: ["rearBowl", "leg", "legFold", "stem"])),
    ("book.svg", layerSVG([path("url(#book)"), path(##"fill="#237D9F""##)], gradients: ["book"])),
]

// MARK: - icon.json

func srgb(_ r: Double, _ g: Double, _ b: Double) -> String {
    String(format: "srgb:%.5f,%.5f,%.5f,1.00000", r / 255, g / 255, b / 255)
}

let iconJSON = """
{
  "fill-specializations" : [
    {
      "value" : {
        "linear-gradient" : [ "\(srgb(255, 255, 255))", "\(srgb(222, 244, 240))" ]
      }
    },
    {
      "appearance" : "dark",
      "value" : {
        "linear-gradient" : [ "\(srgb(52, 53, 56))", "\(srgb(24, 24, 26))" ]
      }
    }
  ],
  "groups" : [
    {
      "name" : "Bubbles",
      "layers" : [
        {
          "name" : "glyphs",
          "image-name" : "glyphs.svg",
          "fill-specializations" : [
            { "appearance" : "dark", "value" : { "solid" : "\(srgb(232, 246, 247))" } }
          ],
          "glass" : true
        },
        { "name" : "bubbles", "image-name" : "bubbles.svg", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.4 },
      "translucency" : { "enabled" : true, "value" : 0.3 }
    },
    {
      "name" : "Ribbon",
      "layers" : [
        { "name" : "ribbon-front", "image-name" : "ribbon-front.svg", "glass" : true },
        { "name" : "ribbon-back", "image-name" : "ribbon-back.svg", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.3 }
    },
    {
      "name" : "Book",
      "layers" : [
        { "name" : "book", "image-name" : "book.svg", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.3 },
      "translucency" : { "enabled" : true, "value" : 0.3 }
    }
  ],
  "supported-platforms" : {
    "squares" : [ "macOS" ]
  }
}

"""

// MARK: - Write the document

let assetsDir = iconDir + "/Assets"
try? fm.removeItem(atPath: assetsDir)                 // no stale layers left behind
try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)
for (name, svg) in layers {
    try svg.write(toFile: assetsDir + "/" + name, atomically: true, encoding: .utf8)
    print("\(name) written")
}
try iconJSON.write(toFile: iconDir + "/icon.json", atomically: true, encoding: .utf8)
print("icon.json written")

// MARK: - Preview PNG for docs, the README and the promo video

func developerDir() -> String? {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    p.arguments = ["-p"]
    p.standardOutput = pipe
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

if let dev = developerDir() {
    let ictool = URL(fileURLWithPath: dev).deletingLastPathComponent()
        .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool").path
    if fm.isExecutableFile(atPath: ictool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ictool)
        p.arguments = [iconDir, "--export-image", "--output-file", previewPath, "--platform", "macOS",
                       "--rendition", "Default", "--width", "1024", "--height", "1024", "--scale", "1"]
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        print(p.terminationStatus == 0 ? "\(previewPath) written" : "ictool failed — preview not updated")
    } else {
        print("ictool not found (Xcode 26+ needed) — preview not updated")
    }
}
print("Done.")
