#!/bin/bash
# Regenerate Resources/ram.pdf from Resources/ram.svg.
#
# The menu bar asset is a PDF rather than the SVG itself for two reasons:
# NSImage has read vector PDF forever (SVG support is far newer than this app's
# macOS 13 floor), and the crop below is baked in once instead of on every draw.
#
# Run this only when the logo or the crop changes; the generated PDF is checked
# in so building never depends on SVG support.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/make-icon.swift" <<'SWIFT'
import AppKit

// herdr's ram sits in the bottom-right of a 512 viewBox with its body running
// off both edges. Shrunk to 18pt that body is a featureless block, so the icon
// crops to the head: the curled horn and the `>-` prompt face are what actually
// identify the mark at menu bar size.
let crop = NSRect(x: 104, y: 132, width: 290, height: 210)   // top-left origin

// A square canvas: the status item keeps the standard square menu bar slot, so
// the ram is fitted inside it rather than scaled up to fill the bar's height.
let canvas: CGFloat = 100
let inset: CGFloat = 4

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon <in.svg> <out.pdf>\n".utf8))
    exit(2)
}
guard let svg = NSImage(contentsOf: URL(fileURLWithPath: arguments[1])) else {
    FileHandle.standardError.write(Data("cannot read \(arguments[1])\n".utf8))
    exit(1)
}

let available = canvas - inset * 2
let scale = min(available / crop.width, available / crop.height)
let width = crop.width * scale, height = crop.height * scale
let originX = (canvas - width) / 2 - crop.minX * scale
// The crop is measured top-left; PDF space is bottom-left, hence the flip.
let originY = (canvas - height) / 2 - (512 - crop.maxY) * scale

var mediaBox = CGRect(x: 0, y: 0, width: canvas, height: canvas)
guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: arguments[2]) as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    FileHandle.standardError.write(Data("cannot create pdf\n".utf8))
    exit(1)
}

context.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
svg.draw(in: NSRect(x: originX, y: originY, width: 512 * scale, height: 512 * scale))
NSGraphicsContext.restoreGraphicsState()
context.endPDFPage()
context.closePDF()
SWIFT

swiftc -O "$WORK/make-icon.swift" -o "$WORK/make-icon"
"$WORK/make-icon" "$ROOT/Resources/ram.svg" "$ROOT/Resources/ram.pdf"
echo "Wrote $ROOT/Resources/ram.pdf"
