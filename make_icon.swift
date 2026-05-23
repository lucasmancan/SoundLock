#!/usr/bin/swift
// Generates the app icon source, README icon, and menu bar template icon.
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

func withFlippedContext(_ context: CGContext, size: CGFloat, draw: () -> Void) {
    context.saveGState()
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    draw()
    context.restoreGState()
}

func drawRoundedPath(_ context: CGContext, rect: CGRect, radius: CGFloat) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
}

func drawSystemSymbol(
    _ symbolName: String,
    in context: CGContext,
    rect: CGRect,
    pointSize: CGFloat,
    color: NSColor,
    weight: NSFont.Weight = .regular,
    mirrored: Bool = false
) {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: .large)
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    guard let tinted = tintedImage(from: symbol, color: color) else { return }
    var proposedRect = CGRect(origin: .zero, size: tinted.size)
    guard let cgImage = tinted.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return }

    context.saveGState()
    if mirrored {
        context.translateBy(x: rect.minX + rect.maxX, y: 0)
        context.scaleBy(x: -1, y: 1)
    }
    context.translateBy(x: 0, y: rect.minY + rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.draw(cgImage, in: rect)
    context.restoreGState()
}

func tintedImage(from image: NSImage, color: NSColor) -> NSImage? {
    let tinted = NSImage(size: image.size)
    tinted.lockFocus()
    let bounds = CGRect(origin: .zero, size: image.size)
    image.draw(in: bounds)
    color.set()
    bounds.fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

func drawHeadphonePriorityMark(in context: CGContext, size: CGFloat, strokeColor: CGColor, soundColor: CGColor) {
    drawSystemSymbol(
        "headphones",
        in: context,
        rect: CGRect(x: size * 0.03, y: size * 0.18, width: size * 0.58, height: size * 0.58),
        pointSize: size * 0.40,
        color: NSColor(cgColor: strokeColor) ?? .white,
        weight: .regular,
        mirrored: false
    )

    let laneHeight = size * 0.115
    let laneX = size * 0.64
    let laneYs = [size * 0.20, size * 0.42, size * 0.64]
    let laneWidths = [size * 0.24, size * 0.20, size * 0.16]
    let laneColors = [soundColor, strokeColor.copy(alpha: 0.92)!, strokeColor.copy(alpha: 0.72)!]

    for index in laneYs.indices {
        let rect = CGRect(
            x: laneX,
            y: laneYs[index],
            width: laneWidths[index],
            height: laneHeight
        )
        context.setFillColor(laneColors[index])
        drawRoundedPath(context, rect: rect, radius: laneHeight / 2)
        context.fillPath()
    }

    let priorityDotRadius = size * 0.044
    context.setFillColor(soundColor)
    context.fillEllipse(in: CGRect(
        x: size * 0.58 - priorityDotRadius,
        y: size * 0.255 - priorityDotRadius,
        width: priorityDotRadius * 2,
        height: priorityDotRadius * 2
    ))
}

extension CGContext {
    func strokeArcSegments(boundingBox: CGRect, startAngle: CGFloat, endAngle: CGFloat) {
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: boundingBox.midX, y: boundingBox.midY),
            radius: boundingBox.height / 2,
            startAngle: startAngle * .pi / 180,
            endAngle: endAngle * .pi / 180,
            clockwise: false
        )
        addPath(path)
        strokePath()
    }
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

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.05, green: 0.15, blue: 0.38, alpha: 1),
            CGColor(srgbRed: 0.07, green: 0.44, blue: 0.74, alpha: 1),
            CGColor(srgbRed: 0.08, green: 0.67, blue: 0.62, alpha: 1)
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    context.resetClip()

    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12))
        context.fillEllipse(in: CGRect(x: size * 0.10, y: size * 0.56, width: size * 0.42, height: size * 0.42))
        context.fillEllipse(in: CGRect(x: size * 0.54, y: size * 0.14, width: size * 0.26, height: size * 0.26))

    withFlippedContext(context, size: size) {
        drawHeadphonePriorityMark(
            in: context,
            size: size,
            strokeColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            soundColor: CGColor(srgbRed: 0.49, green: 1.0, blue: 0.86, alpha: 1)
        )
    }

    let image = context.makeImage()!
    try savePNG(image, to: "soundlock_1024.png")

    let docsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs")
    try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
    try savePNG(image, to: docsDir.appendingPathComponent("icon.png").path)
    try savePNG(image, to: docsDir.appendingPathComponent("readme-icon.png").path)
}

func generateStatusIcon() throws {
    let pixelSize = 96
    let size = CGFloat(pixelSize)
    let context = makeBitmapContext(size: pixelSize, transparent: true)

    withFlippedContext(context, size: size) {
        drawHeadphonePriorityMark(
            in: context,
            size: size,
            strokeColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            soundColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        )
    }

    let image = context.makeImage()!
    try savePNG(image, to: "StatusIcon.png")
}

try generateAppIcon()
try generateStatusIcon()
print("✅  soundlock_1024.png, docs/icon.png, docs/readme-icon.png, and StatusIcon.png saved")
