#!/usr/bin/env swift
//
// gen-icon.swift — emit a minimal PDF by hand (not via CGPDFContext).
//
// Rationale:
//   CGPDFContext always wraps fill colors in ICC-based color spaces
//   (`/Cs1 cs 0 sc`), even when we request DeviceRGB/DeviceGray black.
//   macOS's Fn-hold HUD selected-state tint pipeline apparently only
//   recognizes "uncolored" DeviceGray/DeviceRGB black (`0 g` or
//   `0 0 0 rg`) as tintable foreground — ICC-wrapped black gets left
//   alone, so our glyph paints the literal black pixels and then the
//   HUD tints nothing, leaving the selection pill as a solid color.
//   Squirrel's rime.pdf (Adobe Illustrator-generated) uses raw
//   `0 0 0 rg`, which is what we reproduce here by emitting the PDF
//   bytes directly.
//
// Pipeline: Core Text → CGPath for the glyph outline → serialise the
// path elements to PDF drawing operators → wrap in a minimal 6-object
// PDF skeleton with proper xref table.
//
// usage: swift scripts/gen-icon.swift <out.pdf> <char>

import AppKit
import CoreGraphics
import CoreText

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: gen-icon.swift <out.pdf> <char>\n".utf8))
    exit(2)
}
let outURL = URL(fileURLWithPath: args[1])
let glyph = args[2] as String

// -- Page geometry ----------------------------------------------------
let pageSide: CGFloat = 64

// -- Build the combined glyph path ------------------------------------
let fontSize = pageSide * 0.55
let font = CTFontCreateUIFontForLanguage(.system, fontSize, "zh-Hans" as CFString)
    ?? CTFontCreateWithName("PingFangSC-Semibold" as CFString, fontSize, nil)

let attr = NSAttributedString(
    string: glyph,
    attributes: [.font: font, .foregroundColor: NSColor.black]
)
let line = CTLineCreateWithAttributedString(attr)

let combined = CGMutablePath()
let runs = CTLineGetGlyphRuns(line) as! [CTRun]
for run in runs {
    let glyphCount = CTRunGetGlyphCount(run)
    guard glyphCount > 0 else { continue }
    let runFont = (CTRunGetAttributes(run) as NSDictionary)
        .object(forKey: kCTFontAttributeName) as! CTFont
    var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
    var positions = [CGPoint](repeating: .zero, count: glyphCount)
    CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)
    for i in 0..<glyphCount {
        guard let gPath = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
        let t = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
        combined.addPath(gPath, transform: t)
    }
}

// Center the combined path on the page.
let bbox = combined.boundingBoxOfPath
let tx = (pageSide - bbox.width) / 2 - bbox.minX
let ty = (pageSide - bbox.height) / 2 - bbox.minY - pageSide * 0.01
let centered = CGMutablePath()
centered.addPath(combined, transform: CGAffineTransform(translationX: tx, y: ty))

// -- Serialise CGPath to PDF content operators ------------------------
var pdfOps = ""
func f(_ v: CGFloat) -> String {
    // PDF operators expect space-separated numbers with limited precision.
    String(format: "%.4f", v)
}

centered.applyWithBlock { elemPtr in
    let elem = elemPtr.pointee
    let p = elem.points
    switch elem.type {
    case .moveToPoint:
        pdfOps += "\(f(p[0].x)) \(f(p[0].y)) m\n"
    case .addLineToPoint:
        pdfOps += "\(f(p[0].x)) \(f(p[0].y)) l\n"
    case .addQuadCurveToPoint:
        // PDF has no quadratic — convert to cubic: Q(p1) → C(p0 + 2/3(p1-p0), p2 + 2/3(p1-p2), p2).
        // CGPath applyWithBlock gives us the current point implicitly, but we track it in a closure var.
        break  // handled below; we'll replay separately.
    case .addCurveToPoint:
        pdfOps += "\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y)) c\n"
    case .closeSubpath:
        pdfOps += "h\n"
    @unknown default:
        break
    }
}

// Handle quadratic curves properly — re-iterate tracking current point.
// Most Chinese glyph outlines are cubic, but PingFang may mix both;
// re-run with a current-point tracker to convert any quadratics.
pdfOps = ""
var currentPoint = CGPoint.zero
centered.applyWithBlock { elemPtr in
    let elem = elemPtr.pointee
    let p = elem.points
    switch elem.type {
    case .moveToPoint:
        pdfOps += "\(f(p[0].x)) \(f(p[0].y)) m\n"
        currentPoint = p[0]
    case .addLineToPoint:
        pdfOps += "\(f(p[0].x)) \(f(p[0].y)) l\n"
        currentPoint = p[0]
    case .addQuadCurveToPoint:
        // Convert Q(cp, end) to C(c1, c2, end): c1 = P0 + 2/3(cp-P0), c2 = P2 + 2/3(cp-P2)
        let P0 = currentPoint
        let cp = p[0]
        let P2 = p[1]
        let c1 = CGPoint(x: P0.x + (2.0/3.0) * (cp.x - P0.x), y: P0.y + (2.0/3.0) * (cp.y - P0.y))
        let c2 = CGPoint(x: P2.x + (2.0/3.0) * (cp.x - P2.x), y: P2.y + (2.0/3.0) * (cp.y - P2.y))
        pdfOps += "\(f(c1.x)) \(f(c1.y)) \(f(c2.x)) \(f(c2.y)) \(f(P2.x)) \(f(P2.y)) c\n"
        currentPoint = P2
    case .addCurveToPoint:
        pdfOps += "\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y)) c\n"
        currentPoint = p[2]
    case .closeSubpath:
        pdfOps += "h\n"
    @unknown default:
        break
    }
}

// -- Build the white rounded-rect background --------------------------
// Apple's "A" / Squirrel's icons both have a filled white rounded-rect
// behind the glyph. Without it, the Fn-hold HUD's selection highlight
// fills the whole icon region with the selection accent and there's
// nothing to contrast the dark glyph against (result: solid blue blob).
// With it, the HUD renders the white→tinted-selection-bg and the black
// glyph→inverse tint, yielding the expected "pill + glyph" look.
let inset: CGFloat = pageSide * 0.06
let radius: CGFloat = pageSide * 0.22
let rx = inset, ry = inset
let rw = pageSide - inset * 2, rh = pageSide - inset * 2
// Emit a rounded-rect path as four Bézier arcs around the corners.
// PDF has no native rounded-rect operator, so we build it manually.
// k ≈ 0.5523 is the well-known "circle as cubic Bézier" magic constant.
let k: CGFloat = 0.5523
let a = radius * k
var bg = ""
func ff(_ v: CGFloat) -> String { String(format: "%.4f", v) }
// Start at bottom-left + radius on the x axis, go clockwise.
bg += "\(ff(rx + radius)) \(ff(ry)) m\n"
bg += "\(ff(rx + rw - radius)) \(ff(ry)) l\n"
bg += "\(ff(rx + rw - radius + a)) \(ff(ry)) \(ff(rx + rw)) \(ff(ry + radius - a)) \(ff(rx + rw)) \(ff(ry + radius)) c\n"
bg += "\(ff(rx + rw)) \(ff(ry + rh - radius)) l\n"
bg += "\(ff(rx + rw)) \(ff(ry + rh - radius + a)) \(ff(rx + rw - radius + a)) \(ff(ry + rh)) \(ff(rx + rw - radius)) \(ff(ry + rh)) c\n"
bg += "\(ff(rx + radius)) \(ff(ry + rh)) l\n"
bg += "\(ff(rx + radius - a)) \(ff(ry + rh)) \(ff(rx)) \(ff(ry + rh - radius + a)) \(ff(rx)) \(ff(ry + rh - radius)) c\n"
bg += "\(ff(rx)) \(ff(ry + radius)) l\n"
bg += "\(ff(rx)) \(ff(ry + radius - a)) \(ff(rx + radius - a)) \(ff(ry)) \(ff(rx + radius)) \(ff(ry)) c\n"
bg += "h\n"

// -- Assemble the content stream --------------------------------------
// Draw order: white rounded-rect bg (filled), then black glyph path on top.
// Both use `rg` (DeviceRGB) literals so they're "raw" colors that the
// HUD's tint pipeline can recolor. Squirrel's rime.pdf has this same
// light-bg + dark-glyph shape.
// Color choice matters for Fn-hold HUD selection:
//  - `1 1 1` (white) rect + `0 0 0` (pure black) glyph: the HUD's tint
//    pipeline decides "single-color template" and fills the whole icon
//    region with the selection color → glyph invisible when selected.
//  - Using slightly-off-black (e.g. 0.08) defeats that detection; the
//    HUD renders the icon as-is in every state, so the black glyph on
//    white bg stays visible when selected too.
let contentStream =
    "1 1 1 rg\n" +
    bg +
    "f\n" +
    "0.08 0.08 0.08 rg\n" +
    pdfOps +
    "f\n"
let contentBytes = Data(contentStream.utf8)

// -- Build the PDF document bytes -------------------------------------
// Structure:
//   1 0: Catalog
//   2 0: Pages
//   3 0: Page
//   4 0: Content stream
//   5 0: (none — skipped)
// xref, trailer, startxref, %%EOF

var pdf = Data()
func append(_ s: String) { pdf.append(Data(s.utf8)) }

var offsets: [Int] = []
func recordOffset() { offsets.append(pdf.count) }

append("%PDF-1.3\n")
// Binary marker comment (optional but common, signals 8-bit safe).
pdf.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])

recordOffset()  // obj 1: Catalog
append("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

recordOffset()  // obj 2: Pages
append("2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n")

recordOffset()  // obj 3: Page
append("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(Int(pageSide)) \(Int(pageSide))] " +
       "/Resources << /ProcSet [/PDF] >> /Contents 4 0 R >>\nendobj\n")

recordOffset()  // obj 4: Content stream
append("4 0 obj\n<< /Length \(contentBytes.count) >>\nstream\n")
pdf.append(contentBytes)
append("endstream\nendobj\n")

// xref
let xrefOffset = pdf.count
append("xref\n0 5\n")
append("0000000000 65535 f \n")
for off in offsets {
    append(String(format: "%010d 00000 n \n", off))
}

// trailer
append("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n")

try pdf.write(to: outURL)
FileHandle.standardError.write(Data("wrote \(outURL.path) (\(pdf.count) bytes, hand-written PDF)\n".utf8))
