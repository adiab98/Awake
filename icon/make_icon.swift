#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Render a 1024x1024 macOS-style icon: rounded squircle background + SF Symbol coffee cup.
// Output: ./AppIcon.iconset/ + AppIcon.icns
let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    defer { img.unlockFocus() }

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: macOS-style squircle with vertical gradient (warm coffee tones).
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let radius = (s - 2*inset) * 0.225
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.18, green: 0.12, blue: 0.08, alpha: 1).cgColor,
        NSColor(srgbRed: 0.40, green: 0.27, blue: 0.18, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()

    // Subtle inner highlight.
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(white: 1, alpha: 0.18).cgColor,
            NSColor(white: 1, alpha: 0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.05),
        startRadius: 0,
        endCenter: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.05),
        endRadius: rect.width * 0.55,
        options: []
    )
    ctx.restoreGState()

    // Coffee cup using SF Symbol — large white glyph.
    let pointSize = s * 0.50
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symSize = symbol.size
        let symRect = NSRect(
            x: (s - symSize.width) / 2,
            y: (s - symSize.height) / 2 - s * 0.02,
            width: symSize.width,
            height: symSize.height
        )
        symbol.draw(in: symRect)
    }

    return img
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("PNG encode failed for \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

// Apple's required iconset sizes.
let sizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in sizes {
    let img = render(size: size)
    writePNG(img, to: "\(outDir)/\(name)")
    print("wrote \(name) at \(size)x\(size)")
}

print("Now run: iconutil -c icns \(outDir) -o AppIcon.icns")
