#!/usr/bin/env swift
//
// gen-icon.swift — render a simple PDF icon containing a Chinese character.
//
// usage: swift scripts/gen-icon.swift <out.pdf> <char>
//
// The PDF is used as `tsInputModeMenuIconFileKey` / `CFBundleIconFile`.

import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: gen-icon.swift <out.pdf> <char>\n".utf8))
    exit(2)
}
let outURL = URL(fileURLWithPath: args[1])
let glyph = args[2] as NSString

let side: CGFloat = 64
var mediaBox = CGRect(x: 0, y: 0, width: side, height: side)

guard let consumer = CGDataConsumer(url: outURL as CFURL),
      let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
else {
    FileHandle.standardError.write(Data("failed to open PDF context\n".utf8))
    exit(1)
}

ctx.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// Simple rounded-rect background so the icon reads clearly on both light
// and dark menu bars.
let bg = NSBezierPath(
    roundedRect: NSRect(x: 2, y: 2, width: side - 4, height: side - 4),
    xRadius: 10,
    yRadius: 10
)
NSColor.black.setFill()
bg.fill()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 40),
    .foregroundColor: NSColor.white,
]
let glyphSize = glyph.size(withAttributes: attrs)
let origin = NSPoint(
    x: (side - glyphSize.width) / 2,
    y: (side - glyphSize.height) / 2 - 2
)
glyph.draw(at: origin, withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()
ctx.endPDFPage()
ctx.closePDF()

FileHandle.standardError.write(Data("wrote \(outURL.path)\n".utf8))
