#!/usr/bin/env swift

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

private let canvasW = 2880
private let canvasH = 1800

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let outputDir = root.appendingPathComponent("metadata/screenshots/mac/en-US")
private let appIconURL = root.appendingPathComponent("icon/AppIcon.iconset/icon_512x512@2x.png")

private extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xff) / 255
        let g = CGFloat((value >> 8) & 0xff) / 255
        let b = CGFloat(value & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

private struct Shadow {
    let color: NSColor
    let blur: CGFloat
    let offset: CGSize
}

private func flip(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX, y: CGFloat(canvasH) - rect.minY - rect.height, width: rect.width, height: rect.height)
}

private func flip(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: CGFloat(canvasH) - point.y)
}

private func withState(_ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

private func roundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    fill: NSColor,
    stroke: NSColor? = nil,
    lineWidth: CGFloat = 1,
    shadow: Shadow? = nil
) {
    withState {
        if let shadow {
            let nsShadow = NSShadow()
            nsShadow.shadowColor = shadow.color
            nsShadow.shadowBlurRadius = shadow.blur
            nsShadow.shadowOffset = CGSize(width: shadow.offset.width, height: -shadow.offset.height)
            nsShadow.set()
        }
        let path = NSBezierPath(roundedRect: flip(rect), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        if let stroke {
            stroke.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        }
    }
}

private func rect(_ rect: CGRect, fill: NSColor) {
    fill.setFill()
    NSBezierPath(rect: flip(rect)).fill()
}

private func line(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: flip(from))
    path.line(to: flip(to))
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func polygon(_ points: [CGPoint], fill: NSColor) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: flip(first))
    for point in points.dropFirst() {
        path.line(to: flip(point))
    }
    path.close()
    fill.setFill()
    path.fill()
}

private func text(
    _ value: String,
    in rect: CGRect,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = .black,
    alignment: NSTextAlignment = .left,
    lineHeight: CGFloat = 1.12
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.minimumLineHeight = size * lineHeight
    paragraph.maximumLineHeight = size * lineHeight
    paragraph.lineBreakMode = .byWordWrapping

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    (value as NSString).draw(
        with: flip(rect),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attrs
    )
}

private func pillText(
    _ value: String,
    at origin: CGPoint,
    paddingX: CGFloat,
    height: CGFloat,
    fontSize: CGFloat,
    fill: NSColor,
    color: NSColor,
    stroke: NSColor? = nil
) -> CGRect {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let width = ceil((value as NSString).size(withAttributes: [.font: font]).width + paddingX * 2)
    let box = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    roundedRect(box, radius: height / 2, fill: fill, stroke: stroke, lineWidth: 2)
    text(value, in: CGRect(x: box.minX, y: box.minY + (height - fontSize * 1.12) / 2, width: box.width, height: height), size: fontSize, weight: .semibold, color: color, alignment: .center)
    return box
}

private func drawToggle(_ rect: CGRect, on: Bool) {
    let fill = on ? NSColor(hex: "007AFF") : NSColor(hex: "CCD4DA")
    roundedRect(rect, radius: rect.height / 2, fill: fill, shadow: Shadow(color: NSColor.black.withAlphaComponent(0.10), blur: 12, offset: CGSize(width: 0, height: 4)))
    let knobSize = rect.height - 12
    let knobX = on ? rect.maxX - knobSize - 6 : rect.minX + 6
    roundedRect(CGRect(x: knobX, y: rect.minY + 6, width: knobSize, height: knobSize), radius: knobSize / 2, fill: .white, shadow: Shadow(color: NSColor.black.withAlphaComponent(0.18), blur: 10, offset: CGSize(width: 0, height: 3)))
}

private func drawAppIcon(_ rect: CGRect, radius: CGFloat? = nil) {
    guard let image = NSImage(contentsOf: appIconURL) else {
        roundedRect(rect, radius: radius ?? rect.width * 0.22, fill: NSColor(hex: "523624"))
        text("Awake", in: rect.insetBy(dx: 16, dy: rect.height * 0.38), size: rect.width * 0.12, weight: .bold, color: .white, alignment: .center)
        return
    }

    withState {
        let drawRect = flip(rect)
        let path = NSBezierPath(roundedRect: drawRect, xRadius: radius ?? rect.width * 0.22, yRadius: radius ?? rect.width * 0.22)
        path.addClip()
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

private func drawMenuBar(_ frame: CGRect, activeCup: Bool = true) {
    roundedRect(frame, radius: 0, fill: NSColor.white.withAlphaComponent(0.30))
    let y = frame.minY + 22
    let iconH: CGFloat = frame.height - 44

    let cupBox = CGRect(x: frame.minX + 84, y: y, width: 174, height: iconH)
    roundedRect(cupBox, radius: iconH / 2, fill: activeCup ? NSColor(hex: "FF9F2F") : NSColor.white.withAlphaComponent(0.30))
    text("A", in: cupBox.offsetBy(dx: 0, dy: 5), size: 42, weight: .heavy, color: .white, alignment: .center)

    let centers: [CGFloat] = [338, 450, 562, 678, 790, 910]
    for (idx, cx) in centers.enumerated() {
        let box = CGRect(x: frame.minX + cx, y: y, width: 76, height: iconH)
        if idx == 1 {
            roundedRect(box.insetBy(dx: -18, dy: 0), radius: iconH / 2, fill: NSColor.white.withAlphaComponent(0.18))
        }
        let label = ["", "cup", "AI", "play", "100%", "search"][idx]
        if label.isEmpty {
            roundedRect(CGRect(x: box.midX - 18, y: box.midY - 18, width: 36, height: 36), radius: 18, fill: NSColor.white.withAlphaComponent(0.30))
        } else if label == "cup" {
            text("C", in: box.offsetBy(dx: 0, dy: 7), size: 34, weight: .bold, color: .white, alignment: .center)
        } else if label == "AI" {
            text("AI", in: box.offsetBy(dx: 0, dy: 6), size: 25, weight: .bold, color: .white, alignment: .center)
        } else if label == "play" {
            text(">", in: box.offsetBy(dx: 0, dy: 3), size: 35, weight: .bold, color: .white, alignment: .center)
        } else if label == "100%" {
            text("100%", in: box.offsetBy(dx: 0, dy: 12), size: 24, weight: .bold, color: .white, alignment: .center)
        } else {
            text("Q", in: box.offsetBy(dx: 0, dy: 6), size: 31, weight: .bold, color: .white, alignment: .center)
        }
    }
}

private func drawMenuPopover(_ frame: CGRect, variant: Int) {
    roundedRect(
        frame,
        radius: 52,
        fill: NSColor(hex: "D6ECF7").withAlphaComponent(0.93),
        stroke: NSColor.white.withAlphaComponent(0.82),
        lineWidth: 3,
        shadow: Shadow(color: NSColor.black.withAlphaComponent(0.18), blur: 44, offset: CGSize(width: 0, height: 28))
    )

    let x = frame.minX + 72
    let w = frame.width - 144
    var y = frame.minY + 58

    text("Awake", in: CGRect(x: x, y: y, width: w - 160, height: 62), size: 58, weight: .bold, color: NSColor(hex: "07121E"))
    drawToggle(CGRect(x: frame.maxX - 260, y: y + 10, width: 172, height: 74), on: true)
    y += 76
    let subtitle = variant == 1 ? "Mac won't sleep until Claude finishes" : "Mac stays awake for 45 minutes"
    text(subtitle, in: CGRect(x: x, y: y, width: w - 60, height: 58), size: 36, weight: .medium, color: NSColor(hex: "244458"))
    y += 78

    line(from: CGPoint(x: x, y: y), to: CGPoint(x: x + w, y: y), color: NSColor(hex: "A5C6D4").withAlphaComponent(0.70), width: 3)
    y += 54

    text("Wait for AI agent turn", in: CGRect(x: x, y: y, width: w - 190, height: 56), size: 45, weight: .bold, color: .black)
    drawToggle(CGRect(x: frame.maxX - 260, y: y - 3, width: 172, height: 74), on: true)
    y += 76
    text("Claude: in turn", in: CGRect(x: x, y: y, width: w, height: 50), size: 37, weight: .semibold, color: NSColor(hex: "007AFF"))
    y += 54
    text("Codex: idle", in: CGRect(x: x, y: y, width: w, height: 50), size: 37, weight: .regular, color: NSColor(hex: "34576A"))
    if variant == 2 {
        y += 54
        text("OpenCode: idle", in: CGRect(x: x, y: y, width: w, height: 50), size: 37, weight: .regular, color: NSColor(hex: "34576A"))
    }
    y += 76

    line(from: CGPoint(x: x, y: y), to: CGPoint(x: x + w, y: y), color: NSColor(hex: "A5C6D4").withAlphaComponent(0.70), width: 3)
    y += 54

    text("Timer", in: CGRect(x: x, y: y, width: 240, height: 56), size: 45, weight: .bold, color: .black)
    if variant == 3 {
        roundedRect(CGRect(x: frame.maxX - 340, y: y - 4, width: 250, height: 74), radius: 26, fill: NSColor(hex: "BBDDEA").withAlphaComponent(0.86))
        text("45 min", in: CGRect(x: frame.maxX - 318, y: y + 14, width: 170, height: 44), size: 33, weight: .semibold, color: .black, alignment: .center)
        text("v", in: CGRect(x: frame.maxX - 150, y: y + 15, width: 46, height: 44), size: 28, weight: .bold, color: .black, alignment: .center)
    } else {
        roundedRect(CGRect(x: frame.maxX - 340, y: y - 4, width: 250, height: 74), radius: 26, fill: NSColor(hex: "BBDDEA").withAlphaComponent(0.86))
        text("No timer", in: CGRect(x: frame.maxX - 324, y: y + 14, width: 180, height: 44), size: 33, weight: .semibold, color: .black, alignment: .center)
        text("v", in: CGRect(x: frame.maxX - 150, y: y + 15, width: 46, height: 44), size: 28, weight: .bold, color: .black, alignment: .center)
    }
    y += 82

    if variant == 3 {
        let menu = CGRect(x: frame.maxX - 342, y: y - 4, width: 252, height: 274)
        roundedRect(menu, radius: 24, fill: NSColor(hex: "EAF7FB"), stroke: NSColor(hex: "9DC7D8"), lineWidth: 2, shadow: Shadow(color: NSColor.black.withAlphaComponent(0.13), blur: 22, offset: CGSize(width: 0, height: 10)))
        let options = ["15 min", "30 min", "45 min", "1 hour", "Custom..."]
        for (idx, option) in options.enumerated() {
            let oy = menu.minY + 20 + CGFloat(idx) * 48
            if idx == 2 {
                roundedRect(CGRect(x: menu.minX + 14, y: oy - 5, width: menu.width - 28, height: 42), radius: 13, fill: NSColor(hex: "D4EEF8"))
            }
            text(option, in: CGRect(x: menu.minX + 28, y: oy, width: menu.width - 56, height: 40), size: 27, weight: idx == 2 ? .bold : .medium, color: NSColor(hex: "092033"))
        }
    }

    line(from: CGPoint(x: x, y: y), to: CGPoint(x: x + w, y: y), color: NSColor(hex: "A5C6D4").withAlphaComponent(0.70), width: 3)
    y += 54

    text("Keep display awake", in: CGRect(x: x, y: y, width: w - 190, height: 54), size: 42, weight: .semibold, color: .black)
    drawToggle(CGRect(x: frame.maxX - 260, y: y - 5, width: 172, height: 74), on: true)
    y += 86

    line(from: CGPoint(x: x, y: y), to: CGPoint(x: x + w, y: y), color: NSColor(hex: "A5C6D4").withAlphaComponent(0.70), width: 3)
    y += 48

    text("More", in: CGRect(x: x, y: y, width: w - 60, height: 50), size: 41, weight: .semibold, color: .black)
    text(">", in: CGRect(x: frame.maxX - 138, y: y - 2, width: 48, height: 50), size: 42, weight: .bold, color: NSColor(hex: "244458"), alignment: .right)
    y += 70
    text("Quit", in: CGRect(x: x, y: y, width: w, height: 52), size: 41, weight: .semibold, color: .black)
}

private func drawDesktop(_ frame: CGRect, variant: Int) {
    roundedRect(frame, radius: 90, fill: NSColor(hex: "06101D"), shadow: Shadow(color: NSColor.black.withAlphaComponent(0.26), blur: 56, offset: CGSize(width: 0, height: 24)))
    withState {
        let clippedFrame = frame.insetBy(dx: 22, dy: 22)
        let path = NSBezierPath(roundedRect: flip(clippedFrame), xRadius: 74, yRadius: 74)
        path.addClip()
        let colors = variant == 1
            ? [NSColor(hex: "1B90D1"), NSColor(hex: "77D6E7"), NSColor(hex: "DDF6F4")]
            : [NSColor(hex: "132E46"), NSColor(hex: "20647E"), NSColor(hex: "81D7BA")]
        NSGradient(colors: colors)?.draw(in: flip(clippedFrame), angle: -34)
        polygon([
            CGPoint(x: frame.minX - 120, y: frame.maxY - 420),
            CGPoint(x: frame.maxX + 80, y: frame.maxY - 900),
            CGPoint(x: frame.maxX + 120, y: frame.maxY),
            CGPoint(x: frame.minX - 120, y: frame.maxY)
        ], fill: NSColor.white.withAlphaComponent(0.18))
        polygon([
            CGPoint(x: frame.minX - 90, y: frame.minY + 180),
            CGPoint(x: frame.maxX + 100, y: frame.minY + 680),
            CGPoint(x: frame.maxX + 100, y: frame.minY + 980),
            CGPoint(x: frame.minX - 90, y: frame.minY + 510)
        ], fill: NSColor(hex: "0B71D9").withAlphaComponent(0.20))
        drawMenuBar(CGRect(x: frame.minX + 22, y: frame.minY + 22, width: frame.width - 44, height: 112))
    }
}

private func drawHeroSlide() {
    rect(CGRect(x: 0, y: 0, width: canvasW, height: canvasH), fill: NSColor(hex: "FAF8F2"))

    polygon([
        CGPoint(x: 0, y: canvasH - 410),
        CGPoint(x: 1240, y: canvasH - 660),
        CGPoint(x: 1360, y: canvasH),
        CGPoint(x: 0, y: canvasH)
    ], fill: NSColor(hex: "E7F4F4"))

    let desktop = CGRect(x: -150, y: 190, width: 1390, height: 1420)
    drawDesktop(desktop, variant: 1)
    drawMenuPopover(CGRect(x: 350, y: 350, width: 840, height: 1030), variant: 1)

    drawAppIcon(CGRect(x: 1445, y: 242, width: 126, height: 126))
    text("Awake", in: CGRect(x: 1598, y: 263, width: 420, height: 70), size: 52, weight: .heavy, color: NSColor(hex: "17202A"))
    _ = pillText("MAC MENU BAR", at: CGPoint(x: 1445, y: 432), paddingX: 32, height: 62, fontSize: 27, fill: NSColor(hex: "E9F4F5"), color: NSColor(hex: "087C94"), stroke: NSColor(hex: "BFE2E8"))

    text("Keep your\nMac awake", in: CGRect(x: 1440, y: 548, width: 1100, height: 440), size: 174, weight: .heavy, color: .black, lineHeight: 0.96)
    text(
        "Stop idle sleep while local AI agents and long-running tasks finish.",
        in: CGRect(x: 1450, y: 1050, width: 1040, height: 150),
        size: 50,
        weight: .regular,
        color: NSColor(hex: "17202A"),
        lineHeight: 1.22
    )

    let chipY: CGFloat = 1270
    let first = pillText("One-click wake", at: CGPoint(x: 1450, y: chipY), paddingX: 34, height: 72, fontSize: 30, fill: NSColor(hex: "FFFFFF"), color: NSColor(hex: "17202A"), stroke: NSColor(hex: "D9E2E4"))
    let second = pillText("Display control", at: CGPoint(x: first.maxX + 22, y: chipY), paddingX: 34, height: 72, fontSize: 30, fill: NSColor(hex: "FFFFFF"), color: NSColor(hex: "17202A"), stroke: NSColor(hex: "D9E2E4"))
    _ = pillText("Local only", at: CGPoint(x: second.maxX + 22, y: chipY), paddingX: 34, height: 72, fontSize: 30, fill: NSColor(hex: "FFFFFF"), color: NSColor(hex: "17202A"), stroke: NSColor(hex: "D9E2E4"))
}

private func drawAgentCard(_ frame: CGRect) {
    roundedRect(frame, radius: 44, fill: NSColor(hex: "F5FBFC"), stroke: NSColor.white.withAlphaComponent(0.70), lineWidth: 2, shadow: Shadow(color: NSColor.black.withAlphaComponent(0.26), blur: 50, offset: CGSize(width: 0, height: 26)))
    let x = frame.minX + 58
    text("Agent Activity", in: CGRect(x: x, y: frame.minY + 52, width: frame.width - 116, height: 62), size: 46, weight: .heavy, color: NSColor(hex: "07121E"))
    text("Awake watches local activity signals.", in: CGRect(x: x, y: frame.minY + 116, width: frame.width - 116, height: 52), size: 29, weight: .medium, color: NSColor(hex: "587083"))

    let rows: [(String, String, NSColor, Bool)] = [
        ("Claude Code", "in turn", NSColor(hex: "007AFF"), true),
        ("Codex", "idle", NSColor(hex: "8795A1"), false),
        ("OpenCode", "idle", NSColor(hex: "8795A1"), false),
        ("Cursor", "best effort", NSColor(hex: "C77700"), false)
    ]

    var y = frame.minY + 224
    for (name, state, color, active) in rows {
        roundedRect(CGRect(x: x, y: y, width: frame.width - 116, height: 104), radius: 28, fill: active ? NSColor(hex: "E8F4FF") : NSColor(hex: "EEF3F5"))
        roundedRect(CGRect(x: x + 30, y: y + 34, width: 36, height: 36), radius: 18, fill: color)
        text(name, in: CGRect(x: x + 90, y: y + 27, width: 360, height: 54), size: 34, weight: .bold, color: NSColor(hex: "101820"))
        text(state, in: CGRect(x: frame.maxX - 300, y: y + 30, width: 190, height: 50), size: 30, weight: .bold, color: color, alignment: .right)
        y += 124
    }

    roundedRect(CGRect(x: x, y: frame.maxY - 144, width: frame.width - 116, height: 86), radius: 28, fill: NSColor(hex: "102B3A"))
    text("No cloud account. No transcript upload.", in: CGRect(x: x + 32, y: frame.maxY - 121, width: frame.width - 180, height: 42), size: 29, weight: .bold, color: .white)
}

private func drawTerminalPanel(_ frame: CGRect) {
    roundedRect(frame, radius: 36, fill: NSColor(hex: "08131F"), stroke: NSColor.white.withAlphaComponent(0.08), lineWidth: 2, shadow: Shadow(color: NSColor.black.withAlphaComponent(0.32), blur: 42, offset: CGSize(width: 0, height: 24)))
    let buttons = [NSColor(hex: "FF6159"), NSColor(hex: "FFBD2E"), NSColor(hex: "28C840")]
    for (idx, color) in buttons.enumerated() {
        roundedRect(CGRect(x: frame.minX + 34 + CGFloat(idx) * 34, y: frame.minY + 32, width: 18, height: 18), radius: 9, fill: color)
    }
    let lines = [
        "$ codex run build-release",
        "planning next patch...",
        "writing files...",
        "tests still running"
    ]
    var y = frame.minY + 92
    for (idx, value) in lines.enumerated() {
        text(value, in: CGRect(x: frame.minX + 42, y: y, width: frame.width - 84, height: 42), size: 29, weight: idx == 0 ? .bold : .medium, color: idx == 0 ? NSColor(hex: "88F7C3") : NSColor(hex: "B6C7D1"))
        y += 54
    }
}

private func drawAgentSlide() {
    rect(CGRect(x: 0, y: 0, width: canvasW, height: canvasH), fill: NSColor(hex: "0B1422"))
    NSGradient(colors: [NSColor(hex: "0B1422"), NSColor(hex: "143C4A"), NSColor(hex: "0E221D")])?.draw(in: flip(CGRect(x: 0, y: 0, width: canvasW, height: canvasH)), angle: -32)

    polygon([
        CGPoint(x: 0, y: 0),
        CGPoint(x: 1020, y: 0),
        CGPoint(x: 540, y: canvasH),
        CGPoint(x: 0, y: canvasH)
    ], fill: NSColor(hex: "1B6B87").withAlphaComponent(0.22))
    polygon([
        CGPoint(x: canvasW - 760, y: 0),
        CGPoint(x: canvasW, y: 0),
        CGPoint(x: canvasW, y: canvasH),
        CGPoint(x: canvasW - 1260, y: canvasH)
    ], fill: NSColor(hex: "7FE7C3").withAlphaComponent(0.11))

    drawAppIcon(CGRect(x: 228, y: 238, width: 122, height: 122))
    _ = pillText("AI AGENT AWARE", at: CGPoint(x: 228, y: 440), paddingX: 34, height: 64, fontSize: 28, fill: NSColor.white.withAlphaComponent(0.10), color: NSColor(hex: "9DF1D1"), stroke: NSColor.white.withAlphaComponent(0.16))
    text("Wait for\nAI turns", in: CGRect(x: 220, y: 560, width: 950, height: 390), size: 168, weight: .heavy, color: .white, lineHeight: 0.96)
    text(
        "Awake keeps macOS active while supported local tools are still working, then lets sleep resume.",
        in: CGRect(x: 228, y: 1045, width: 930, height: 190),
        size: 47,
        weight: .regular,
        color: NSColor(hex: "C8D6DE"),
        lineHeight: 1.22
    )
    _ = pillText("Claude Code", at: CGPoint(x: 228, y: 1302), paddingX: 30, height: 68, fontSize: 28, fill: NSColor(hex: "EAF8FF"), color: NSColor(hex: "0A2942"))
    _ = pillText("Codex", at: CGPoint(x: 510, y: 1302), paddingX: 30, height: 68, fontSize: 28, fill: NSColor(hex: "EAF8FF"), color: NSColor(hex: "0A2942"))
    _ = pillText("OpenCode", at: CGPoint(x: 700, y: 1302), paddingX: 30, height: 68, fontSize: 28, fill: NSColor(hex: "EAF8FF"), color: NSColor(hex: "0A2942"))

    drawTerminalPanel(CGRect(x: 1240, y: 316, width: 1190, height: 440))
    drawAgentCard(CGRect(x: 1420, y: 510, width: 1060, height: 970))
}

private func drawTimerSlide() {
    rect(CGRect(x: 0, y: 0, width: canvasW, height: canvasH), fill: NSColor(hex: "F5FBF7"))
    NSGradient(colors: [NSColor(hex: "F5FBF7"), NSColor(hex: "E8F5FF"), NSColor(hex: "FFF3E2")])?.draw(in: flip(CGRect(x: 0, y: 0, width: canvasW, height: canvasH)), angle: -28)

    polygon([
        CGPoint(x: 0, y: canvasH - 280),
        CGPoint(x: canvasW, y: canvasH - 610),
        CGPoint(x: canvasW, y: canvasH),
        CGPoint(x: 0, y: canvasH)
    ], fill: NSColor(hex: "DFF4EA").withAlphaComponent(0.72))
    polygon([
        CGPoint(x: 0, y: 0),
        CGPoint(x: 750, y: 0),
        CGPoint(x: 420, y: canvasH),
        CGPoint(x: 0, y: canvasH)
    ], fill: NSColor(hex: "FFE3C0").withAlphaComponent(0.55))

    let desktop = CGRect(x: 1120, y: 215, width: 1530, height: 1320)
    drawDesktop(desktop, variant: 2)
    drawMenuPopover(CGRect(x: 1330, y: 372, width: 900, height: 1080), variant: 3)

    roundedRect(CGRect(x: 2050, y: 725, width: 665, height: 600), radius: 42, fill: NSColor(hex: "FFFFFF").withAlphaComponent(0.92), stroke: NSColor(hex: "DCE8EA"), lineWidth: 2, shadow: Shadow(color: NSColor.black.withAlphaComponent(0.16), blur: 42, offset: CGSize(width: 0, height: 22)))
    text("More", in: CGRect(x: 2110, y: 780, width: 300, height: 56), size: 43, weight: .heavy, color: NSColor(hex: "07121E"))
    text("Launch Awake at login", in: CGRect(x: 2110, y: 882, width: 430, height: 46), size: 31, weight: .bold, color: NSColor(hex: "07121E"))
    drawToggle(CGRect(x: 2555, y: 872, width: 108, height: 52), on: true)
    line(from: CGPoint(x: 2110, y: 975), to: CGPoint(x: 2655, y: 975), color: NSColor(hex: "E2EAED"), width: 2)
    text("AI tools to wait for", in: CGRect(x: 2110, y: 1025, width: 430, height: 44), size: 31, weight: .bold, color: NSColor(hex: "07121E"))
    let tools = ["Claude Code", "Codex", "OpenCode"]
    for (idx, tool) in tools.enumerated() {
        let rowY = 1090 + CGFloat(idx) * 66
        text(tool, in: CGRect(x: 2110, y: rowY, width: 330, height: 40), size: 27, weight: .medium, color: NSColor(hex: "263847"))
        drawToggle(CGRect(x: 2578, y: rowY - 5, width: 86, height: 42), on: idx < 2)
    }

    drawAppIcon(CGRect(x: 218, y: 246, width: 122, height: 122))
    _ = pillText("TIMER + DISPLAY", at: CGPoint(x: 218, y: 440), paddingX: 34, height: 64, fontSize: 28, fill: NSColor(hex: "FFFFFF").withAlphaComponent(0.72), color: NSColor(hex: "0B7A58"), stroke: NSColor(hex: "CFE8DB"))
    text("Set a\nwake timer", in: CGRect(x: 210, y: 560, width: 900, height: 360), size: 156, weight: .heavy, color: .black, lineHeight: 0.96)
    text(
        "Start a quick manual session, keep the display on, or launch Awake automatically when you log in.",
        in: CGRect(x: 218, y: 1040, width: 900, height: 190),
        size: 47,
        weight: .regular,
        color: NSColor(hex: "263847"),
        lineHeight: 1.22
    )

    let a = pillText("15 min", at: CGPoint(x: 218, y: 1300), paddingX: 34, height: 72, fontSize: 30, fill: NSColor(hex: "FFFFFF"), color: NSColor(hex: "17202A"), stroke: NSColor(hex: "D9E2E4"))
    let b = pillText("45 min", at: CGPoint(x: a.maxX + 22, y: 1300), paddingX: 34, height: 72, fontSize: 30, fill: NSColor(hex: "FFFFFF"), color: NSColor(hex: "17202A"), stroke: NSColor(hex: "D9E2E4"))
    _ = pillText("Custom", at: CGPoint(x: b.maxX + 22, y: 1300), paddingX: 34, height: 72, fontSize: 30, fill: NSColor(hex: "FFFFFF"), color: NSColor(hex: "17202A"), stroke: NSColor(hex: "D9E2E4"))
}

private func render(_ name: String, draw: () -> Void) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: nil,
        width: canvasW,
        height: canvasH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw NSError(domain: "AwakeScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
    }

    context.interpolationQuality = .high
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    draw()
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage() else {
        throw NSError(domain: "AwakeScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create CGImage"])
    }

    let url = outputDir.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "AwakeScreenshots", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "AwakeScreenshots", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not write \(url.path)"])
    }
    print("Wrote \(url.path)")
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
try render("01-keep-your-mac-awake.png", draw: drawHeroSlide)
try render("02-wait-for-ai-turns.png", draw: drawAgentSlide)
try render("03-set-a-wake-timer.png", draw: drawTimerSlide)
