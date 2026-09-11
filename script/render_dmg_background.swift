#!/usr/bin/env xcrun swift
// Render the DMG window background for a channel as @1x and @2x PNGs, then
// combine them into the committed HiDPI TIFF that script/package_dmg.sh uses:
//
//   ./script/render_dmg_background.swift nightly /tmp/dmg
//   tiffutil -cathidpicheck /tmp/dmg/background-nightly.png /tmp/dmg/background-nightly@2x.png \
//     -out Config/DMG/background-nightly.tiff
//
// Finder always draws icon labels in dark text on a picture background, even in
// Dark Mode, so the design stays light and uses the channel colors as accents.
// Layout must match package_dmg.sh: a 660×440 background, app icon centered at
// (170, 210), Applications link at (490, 210). Everything important stays above
// y = 400 because Finder's optional path bar covers the bottom of the window.

import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count == 3, ["stable", "nightly"].contains(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: render_dmg_background.swift <stable|nightly> <output-directory>\n".utf8))
    exit(2)
}
let channel = arguments[1]
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

struct Theme {
    let name: String
    let start: NSColor
    let end: NSColor
    let footer: String
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let theme = channel == "nightly"
    ? Theme(name: "BriskEdit", start: rgb(0x4C1D95), end: rgb(0xC026D3),
            footer: "Built from dev  ·  Installs next to BriskEdit  ·  Updates itself")
    : Theme(name: "BriskEdit", start: rgb(0x2F3BF0), end: rgb(0x009DFF),
            footer: "Opens instantly  ·  Uses the tools on your Mac  ·  No Electron")

let size = CGSize(width: 660, height: 440)
let appCenter = CGPoint(x: 170, y: 210)
let applicationsCenter = CGPoint(x: 490, y: 210)

func draw(in context: CGContext) {
    // Work top-down like the Finder layout coordinates.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Base: near-white with a faint cool gradient.
    let base = CGGradient(colorsSpace: space, colors: [rgb(0xFBFBFE).cgColor, rgb(0xF0F1F8).cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

    // Soft channel-colored glows in opposite corners.
    for (center, color, radius) in [
        (CGPoint(x: 40, y: 20), theme.start, CGFloat(330)),
        (CGPoint(x: 640, y: 430), theme.end, CGFloat(380)),
    ] {
        let glow = CGGradient(colorsSpace: space, colors: [color.withAlphaComponent(0.20).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    // Quiet dot grid for an editor feel.
    context.setFillColor(rgb(0x1F2937, 0.07).cgColor)
    stride(from: CGFloat(10), to: size.width, by: 20).forEach { x in
        stride(from: CGFloat(10), to: size.height, by: 20).forEach { y in
            context.fillEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
        }
    }

    // Frosted wells behind the two icons; Finder draws the labels inside them.
    for center in [appCenter, applicationsCenter] {
        let well = CGRect(x: center.x - 96, y: center.y - 92, width: 192, height: 196)
        let path = CGPath(roundedRect: well, cornerWidth: 32, cornerHeight: 32, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 6), blur: 24, color: rgb(0x1E1B4B, 0.10).cgColor)
        context.addPath(path)
        context.setFillColor(rgb(0xFFFFFF, 0.78).cgColor)
        context.fillPath()
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(rgb(0xFFFFFF, 0.95).cgColor)
        context.setLineWidth(1)
        context.strokePath()
    }

    // Gradient arrow from the app to Applications.
    let arrowY = appCenter.y - 8
    let shaft = CGMutablePath()
    shaft.move(to: CGPoint(x: 284, y: arrowY))
    shaft.addLine(to: CGPoint(x: 370, y: arrowY))
    shaft.move(to: CGPoint(x: 356, y: arrowY - 13))
    shaft.addLine(to: CGPoint(x: 372, y: arrowY))
    shaft.addLine(to: CGPoint(x: 356, y: arrowY + 13))
    context.saveGState()
    context.addPath(shaft.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 1))
    context.clip()
    let arrow = CGGradient(colorsSpace: space, colors: [theme.start.cgColor, theme.end.cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(arrow, start: CGPoint(x: 280, y: 0), end: CGPoint(x: 378, y: 0), options: [])
    context.restoreGState()

    // Title, optional channel pill, and footer.
    let titleFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
    let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: rgb(0x111827)]
    let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: rgb(0x4B5563)]
    let footerAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: rgb(0x6B7280)]

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let title = NSAttributedString(string: theme.name, attributes: titleAttributes)
    let pillText = NSAttributedString(string: "NIGHTLY", attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .heavy), .foregroundColor: NSColor.white, .kern: 1.2,
    ])
    let showsPill = channel == "nightly"
    let pillSize = CGSize(width: pillText.size().width + 16, height: 18)
    let titleWidth = title.size().width + (showsPill ? pillSize.width + 10 : 0)
    let titleOrigin = CGPoint(x: (size.width - titleWidth) / 2, y: 40)
    title.draw(at: titleOrigin)
    if showsPill {
        let pill = CGRect(x: titleOrigin.x + title.size().width + 10, y: titleOrigin.y + 6, width: pillSize.width, height: pillSize.height)
        let pillPath = NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9)
        NSGradient(starting: theme.start, ending: theme.end)?.draw(in: pillPath, angle: 0)
        pillText.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 2.5))
    }
    let subtitle = NSAttributedString(string: "Drag the app into Applications to install", attributes: subtitleAttributes)
    subtitle.draw(at: CGPoint(x: (size.width - subtitle.size().width) / 2, y: 72))
    let footer = NSAttributedString(string: theme.footer, attributes: footerAttributes)
    footer.draw(at: CGPoint(x: (size.width - footer.size().width) / 2, y: 356))
    NSGraphicsContext.restoreGraphicsState()
}

func render(scale: CGFloat, to url: URL) throws {
    let width = Int(size.width * scale), height = Int(size.height * scale)
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }
    context.scaleBy(x: scale, y: scale)
    draw(in: context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    rep.size = size
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try render(scale: 1, to: outputDirectory.appendingPathComponent("background-\(channel).png"))
try render(scale: 2, to: outputDirectory.appendingPathComponent("background-\(channel)@2x.png"))
print("rendered \(channel) DMG background")
