#!/usr/bin/swift
// Generates the app icon source, README icon, and menu bar template icons.
// Mark: a speaker glyph with a small padlock badge at the bottom-right.
import Foundation
import CoreGraphics
import AppKit

let colorSpace = CGColorSpaceCreateDeviceRGB()

func makeBitmapContext(size: Int, transparent: Bool = false) -> CGContext {
    let alphaInfo: CGImageAlphaInfo = transparent ? .premultipliedLast : .premultipliedFirst
    return CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue).rawValue
    )!
}

func savePNG(_ image: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: path))
}

/// Draws the speaker + padlock mark.
///
/// Geometry is authored in a 100×100, top-left-origin (SVG-style, y-down) design
/// space and mapped into the context's native bottom-left-origin coordinates via
/// `point`, so no global context flip is required.
func drawSpeakerLockMark(in context: CGContext, size: CGFloat, color: CGColor, shackleOpen: Bool) {
    let f = size / 100
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * f, y: (100 - y) * f) }

    // Speaker driver (rect) + cone (triangle), as one filled polygon.
    let speaker = CGMutablePath()
    speaker.move(to: point(14, 38))
    speaker.addLine(to: point(30, 38))
    speaker.addLine(to: point(52, 22))
    speaker.addLine(to: point(52, 78))
    speaker.addLine(to: point(30, 62))
    speaker.addLine(to: point(14, 62))
    speaker.closeSubpath()
    context.addPath(speaker)
    context.setFillColor(color)
    context.fillPath()

    // Lock body (filled rounded rect): SVG x62 y62 w26 h21 → native y17..38.
    let body = CGPath(
        roundedRect: CGRect(x: 62 * f, y: 17 * f, width: 26 * f, height: 21 * f),
        cornerWidth: 5 * f,
        cornerHeight: 5 * f,
        transform: nil
    )
    context.addPath(body)
    context.setFillColor(color)
    context.fillPath()

    // Shackle (stroked arch). Closed: legs meet the body top. Open: lifted, asymmetric legs.
    // clockwise:true bulges the arc upward in the context's native (y-up) space.
    let shackle = CGMutablePath()
    if shackleOpen {
        shackle.move(to: point(67, 59))
        shackle.addLine(to: point(67, 47))
        shackle.addArc(center: point(75, 47), radius: 8 * f, startAngle: .pi, endAngle: 0, clockwise: true)
        shackle.addLine(to: point(83, 49))
    } else {
        shackle.move(to: point(67, 62))
        shackle.addLine(to: point(67, 57))
        shackle.addArc(center: point(75, 57), radius: 8 * f, startAngle: .pi, endAngle: 0, clockwise: true)
        shackle.addLine(to: point(83, 62))
    }
    context.addPath(shackle)
    context.setStrokeColor(color)
    context.setLineWidth(6 * f)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
}

func generateAppIcon() throws {
    let pixelSize = 1024
    let size = CGFloat(pixelSize)
    let context = makeBitmapContext(size: pixelSize)

    let squircle = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: 224,
        cornerHeight: 224,
        transform: nil
    )
    context.addPath(squircle)
    context.clip()

    // Deep indigo, subtle gradient (#2a2d6e → #171a45 → #101230).
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.165, green: 0.176, blue: 0.431, alpha: 1),
            CGColor(srgbRed: 0.090, green: 0.102, blue: 0.271, alpha: 1),
            CGColor(srgbRed: 0.063, green: 0.071, blue: 0.188, alpha: 1)
        ] as CFArray,
        locations: [0, 0.70, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: size * 0.18, y: size),
        end: CGPoint(x: size * 0.82, y: 0),
        options: []
    )
    context.resetClip()

    drawSpeakerLockMark(
        in: context,
        size: size,
        color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        shackleOpen: false
    )

    let image = context.makeImage()!
    try savePNG(image, to: "soundlock_1024.png")

    let docsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs")
    try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
    try savePNG(image, to: docsDir.appendingPathComponent("icon.png").path)
    try savePNG(image, to: docsDir.appendingPathComponent("readme-icon.png").path)
}

/// Menu bar template icon. Generated twice: locked (full opacity) and unlocked
/// (open shackle, dimmed). Template rendering preserves the baked-in alpha as tint.
func generateStatusIcon(open: Bool, alpha: CGFloat, to path: String) throws {
    let pixelSize = 96
    let size = CGFloat(pixelSize)
    let context = makeBitmapContext(size: pixelSize, transparent: true)

    drawSpeakerLockMark(
        in: context,
        size: size,
        color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
        shackleOpen: open
    )

    let image = context.makeImage()!
    try savePNG(image, to: path)
}

try generateAppIcon()
try generateStatusIcon(open: false, alpha: 1.0, to: "StatusIcon.png")
try generateStatusIcon(open: true, alpha: 0.55, to: "StatusIconUnlocked.png")
print("✅  soundlock_1024.png, docs/icon.png, docs/readme-icon.png, StatusIcon.png, and StatusIconUnlocked.png saved")
