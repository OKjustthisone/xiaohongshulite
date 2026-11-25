#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output_iconset_dir>\n", stderr)
    exit(1)
}

let iconsetDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> NSImage {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let image = NSImage(size: size)
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: size)
    let inset = CGFloat(pixelSize) * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = cardRect.width * 0.22

    // Coral Red Gradient Background (Xiaohongshu signature red)
    let path = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.34, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.89, green: 0.08, blue: 0.20, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -90)

    // Subtle top highlight
    NSColor.white.withAlphaComponent(0.14).setStroke()
    path.lineWidth = max(1, CGFloat(pixelSize) * 0.012)
    path.stroke()

    // Crisp minimal "红" / bookmark-leaf glyph in white
    let cx = rect.midX
    let cy = rect.midY
    let w = cardRect.width

    // Draw a stylized notebook / bookmark icon representing RedNote Lite
    let bookW = w * 0.48
    let bookH = w * 0.56
    let bookRect = NSRect(x: cx - bookW / 2, y: cy - bookH / 2, width: bookW, height: bookH)
    let bookPath = NSBezierPath(roundedRect: bookRect, xRadius: w * 0.08, yRadius: w * 0.08)
    NSColor.white.setFill()
    bookPath.fill()

    // Small bookmark ribbon cutout at top-right of the card
    let ribbonW = bookW * 0.24
    let ribbonH = bookH * 0.34
    let rx = bookRect.maxX - ribbonW - bookW * 0.14
    let ry = bookRect.maxY - ribbonH
    let ribbon = NSBezierPath()
    ribbon.move(to: NSPoint(x: rx, y: bookRect.maxY + 1))
    ribbon.line(to: NSPoint(x: rx + ribbonW, y: bookRect.maxY + 1))
    ribbon.line(to: NSPoint(x: rx + ribbonW, y: ry))
    ribbon.line(to: NSPoint(x: rx + ribbonW / 2, y: ry + ribbonH * 0.28))
    ribbon.line(to: NSPoint(x: rx, y: ry))
    ribbon.close()
    NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.24, alpha: 1.0).setFill()
    ribbon.fill()

    // Subtle lines inside notebook
    let lineColor = NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.24, alpha: 0.28)
    lineColor.setFill()
    let lineH = max(2, w * 0.036)
    let lineX = bookRect.minX + bookW * 0.16
    let line1 = NSRect(x: lineX, y: bookRect.minY + bookH * 0.42, width: bookW * 0.66, height: lineH)
    let line2 = NSRect(x: lineX, y: bookRect.minY + bookH * 0.24, width: bookW * 0.46, height: lineH)
    NSBezierPath(roundedRect: line1, xRadius: lineH / 2, yRadius: lineH / 2).fill()
    NSBezierPath(roundedRect: line2, xRadius: lineH / 2, yRadius: lineH / 2).fill()

    image.unlockFocus()
    return image
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    let img = renderIcon(pixelSize: px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    let outPath = (iconsetDir as NSString).appendingPathComponent(filename)
    try png.write(to: URL(fileURLWithPath: outPath))
}
print("Generated iconset at \(iconsetDir)")
