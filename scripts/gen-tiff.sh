#!/bin/bash
#
# gen-tiff.sh — render a Chinese character into a HiDPI TIFF for the TIS
# input-mode menu / Fn HUD.
#
#   - RGB + alpha (samplesPerPixel=4), NOT grayscale
#   - Complete light rounded badge + dark glyph, matching Squirrel's
#     non-template icon approach. Do not use TISIconIsTemplate with this:
#     template rendering flattens the badge and glyph into one mask.
#   - The glyph is centered by scanning its actual rasterized ink bounds,
#     not by trusting font metrics. CJK glyph metrics include side bearings
#     that are visually off-center at this tiny size. A tiny optical y-offset
#     then lowers "两" because its visual weight sits in the top half.
#   - Uses Squirrel-like 22×16 plus 44×32 @2x proportions.
#   - TIFF built by tiffutil, yielding unassociated alpha + LZW compression
# Keeping the resource to the small reps matters on macOS 26: the input
# switcher / Fn HUD can pick a larger rep from third-party IME bundles and
# then scale it like an app icon.
#
# usage: bash scripts/gen-tiff.sh <out.tiff> <char>

set -euo pipefail

OUT="${1:?out.tiff path}"
CHAR="${2:?char}"
TMP="$(mktemp -d /private/tmp/cqlb-tiff.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
    SWIFT_CMD=(xcrun swift)
else
    SWIFT_CMD=(swift)
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$TMP/clang-module-cache}"

"${SWIFT_CMD[@]}" - "$TMP/cqlb.png" "$TMP/cqlb@2x.png" "$CHAR" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
let glyph = args[3] as NSString

let outputs: [(URL, Int, Int)] = {
    // Squirrel's menu PDF is 22×16 points. Use the same aspect ratio so
    // cqlb does not look narrower than the adjacent input-source badges.
    return [
        (URL(fileURLWithPath: args[1]), 22, 16),
        (URL(fileURLWithPath: args[2]), 44, 32),
    ]
}()

for (outURL, pixelWidth, pixelHeight) in outputs {
    let width = CGFloat(pixelWidth)
    let height = CGFloat(pixelHeight)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,  // matches what NSImage returns for Apple's file
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        FileHandle.standardError.write(Data("failed to allocate RGB rep\n".utf8))
        exit(1)
    }

    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Fill the full 22x16 icon canvas. Squirrel's menu badge uses this
    // edge-to-edge proportion; leaving transparent inset makes cqlb look
    // visibly smaller in the input switcher.
    let bgInset: CGFloat = 0
    let bgRect = NSRect(
        x: bgInset,
        y: bgInset,
        width: width - bgInset * 2,
        height: height - bgInset * 2
    )
    NSColor(
        calibratedRed: 0.93,
        green: 0.94,
        blue: 0.93,
        alpha: 1
    ).setFill()
    NSBezierPath(
        roundedRect: bgRect,
        xRadius: height * 0.24,
        yRadius: height * 0.24
    ).fill()

    // Draw the glyph to a transparent offscreen mask first, then center its
    // actual ink bounds inside the badge. Font metrics alone place "两"
    // a hair off-center at 16 px.
    let glyphRed: CGFloat = 0.09
    let glyphGreen: CGFloat = 0.10
    let glyphBlue: CGFloat = 0.10
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: height * 0.72, weight: .bold),
        .foregroundColor: NSColor(
            calibratedRed: glyphRed,
            green: glyphGreen,
            blue: glyphBlue,
            alpha: 1
        ),
    ]
    let glyphSize = glyph.size(withAttributes: attrs)
    let initialOrigin = NSPoint(
        x: (width - glyphSize.width) / 2,
        y: (height - glyphSize.height) / 2
    )
    guard let glyphRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        FileHandle.standardError.write(Data("failed to allocate glyph rep\n".utf8))
        exit(1)
    }
    glyphRep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: glyphRep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    glyph.draw(at: initialOrigin, withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()

    var minX = pixelWidth
    var minY = pixelHeight
    var maxX = -1
    var maxY = -1
    for y in 0..<pixelHeight {
        for x in 0..<pixelWidth {
            let alpha = glyphRep.colorAt(x: x, y: y)?.alphaComponent ?? 0
            // Center by the visible ink core rather than faint antialiasing
            // fringes. A low threshold pulls the tiny 16 px glyph upward.
            if alpha > 0.5 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    if maxX >= minX && maxY >= minY {
        let inkCenterX = (CGFloat(minX + maxX) + 1) / 2
        let inkCenterY = (CGFloat(minY + maxY) + 1) / 2
        let targetCenterX = CGFloat(pixelWidth) / 2
        let targetCenterY = CGFloat(pixelHeight) / 2
        let shiftX = Int((targetCenterX - inkCenterX).rounded())
        let opticalShiftY = max(1, pixelHeight / 16)
        let shiftY = Int((targetCenterY - inkCenterY).rounded()) + opticalShiftY

        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                guard let source = glyphRep.colorAt(x: x, y: y) else { continue }
                let glyphAlpha = source.alphaComponent
                if glyphAlpha <= 0.01 { continue }

                let destX = x + shiftX
                let destY = y + shiftY
                if destX < 0 || destX >= pixelWidth || destY < 0 || destY >= pixelHeight {
                    continue
                }

                let base = (rep.colorAt(x: destX, y: destY) ?? .clear)
                    .usingColorSpace(.deviceRGB) ?? .clear
                let baseAlpha = base.alphaComponent
                let outAlpha = glyphAlpha + baseAlpha * (1 - glyphAlpha)
                if outAlpha <= 0 { continue }

                let outRed = (glyphRed * glyphAlpha + base.redComponent * baseAlpha * (1 - glyphAlpha)) / outAlpha
                let outGreen = (glyphGreen * glyphAlpha + base.greenComponent * baseAlpha * (1 - glyphAlpha)) / outAlpha
                let outBlue = (glyphBlue * glyphAlpha + base.blueComponent * baseAlpha * (1 - glyphAlpha)) / outAlpha
                rep.setColor(
                    NSColor(
                        calibratedRed: outRed,
                        green: outGreen,
                        blue: outBlue,
                        alpha: outAlpha
                    ),
                    atX: destX,
                    y: destY
                )
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to emit PNG\n".utf8))
        exit(1)
    }
    try png.write(to: outURL)
}
SWIFT

# tiffutil recognizes the @2x name, writes 72/144 DPI reps, and produces the
# same alpha/compression style Apple ships for its own input-mode icons.
tiffutil -cathidpicheck "$TMP/cqlb.png" "$TMP/cqlb@2x.png" -out "$TMP/cqlb.raw.tiff" >/dev/null
tiffutil -lzw "$TMP/cqlb.raw.tiff" -out "$OUT" >/dev/null

echo "wrote $OUT (22×16 + 44×32 @2x label TIFF)" >&2
