#!/bin/bash
#
# gen-icns.sh — render a Chinese character into a multi-resolution .icns
# file suitable for CFBundleIconFile.
#
# Visual style: opaque white rounded-rect background + centered dark
# glyph. Fixed visual that reads cleanly in app-icon contexts such as
# System Settings. Matches Squirrel's bundled app icon treatment.
#
# usage: bash scripts/gen-icns.sh <out.icns> <char>

set -euo pipefail

OUT="${1:?out.icns path}"
CHAR="${2:?char}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
    SWIFT_CMD=(xcrun swift)
else
    SWIFT_CMD=(swift)
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$TMP/clang-module-cache}"

ICONSET="$TMP/icon.iconset"
mkdir -p "$ICONSET"

for size_tag in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
                "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
                "512 512x512" "1024 512x512@2x"; do
    set -- $size_tag
    px="$1"; name="$2"
    "${SWIFT_CMD[@]}" - "$ICONSET/icon_$name.png" "$CHAR" "$px" <<'SWIFT'
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let outURL = URL(fileURLWithPath: args[1])
let glyph = args[2] as NSString
let side = CGFloat(Int(args[3]) ?? 128)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side),
    pixelsHigh: Int(side),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else {
    exit(1)
}

rep.size = NSSize(width: side, height: side)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: side, height: side)
NSColor.clear.setFill()
rect.fill()

do {
    // White rounded-square background on Apple's macOS icon grid: an
    // 824pt body in a 1024pt canvas (≈9.8% margin), corner radius ≈185pt.
    let inset = side * (100.0 / 1024.0)
    let bgRect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = side * (185.0 / 1024.0)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.98, green: 0.979, blue: 0.975, alpha: 1).setFill()
    bg.fill()

    // Center the glyph by its actual ink bounds, not by font metrics.
    // `NSString.size` returns the typographic line box (ascent + descent);
    // a CJK glyph's ink sits below the middle of that box, so metric
    // centering — plus the old fixed downward nudge — left the character
    // visibly low in the tile.
    let font = NSFont.boldSystemFont(ofSize: side * 0.52)
    let attributed = NSAttributedString(string: glyph as String, attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.085, blue: 0.09, alpha: 1),
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(
        x: bgRect.midX - ink.midX,
        y: bgRect.midY - ink.midY
    )
    CTLineDraw(line, ctx)
}
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render PNG\n".utf8))
    exit(1)
}
try png.write(to: outURL)
SWIFT
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
