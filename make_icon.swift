#!/usr/bin/swift
// Generates soundlock_1024.png
// Simple headphones silhouette on gradient squircle.
// CG bitmap context: Y=0 = bottom of image; HIGH Y = displayed near top.
import Foundation
import CoreGraphics
import AppKit

let S    = 1024
let size = CGFloat(S)
let cs   = CGColorSpaceCreateDeviceRGB()

let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                   space: cs,
                   bitmapInfo: CGBitmapInfo(rawValue:
                       CGImageAlphaInfo.premultipliedFirst.rawValue).rawValue)!

// ── 1. Squircle gradient background ──────────────────────────────────────
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                    cornerWidth: 224, cornerHeight: 224, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

let grad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(srgbRed: 0.20, green: 0.42, blue: 0.94, alpha: 1),
        CGColor(srgbRed: 0.44, green: 0.22, blue: 0.84, alpha: 1),
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad,
    start: CGPoint(x: 0,    y: size),
    end:   CGPoint(x: size, y: 0),
    options: [])
ctx.resetClip()

let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

// ── 2. Headphones ─────────────────────────────────────────────────────────
let cx: CGFloat = size / 2
let cy: CGFloat = 552                 // CG Y of headband arc center

// 2a. Headband — thick stroked top-half arc (∩ in displayed orientation)
let bandR:  CGFloat = 300
let bandLW: CGFloat = 70

ctx.setStrokeColor(white)
ctx.setLineWidth(bandLW)
ctx.setLineCap(.round)

let band = CGMutablePath()
band.addArc(center: CGPoint(x: cx, y: cy),
            radius: bandR,
            startAngle: 0, endAngle: .pi,
            clockwise: false)
ctx.addPath(band)
ctx.strokePath()

// 2b. Earcups — rounded rects hanging from each arc end
let cupW: CGFloat = 200
let cupH: CGFloat = 260
let cupR: CGFloat = 56

let cupTopCG = cy
let cupMinCG = cupTopCG - cupH

ctx.setFillColor(white)
let leftCup = CGRect(x: cx - bandR - cupW / 2, y: cupMinCG,
                     width: cupW, height: cupH)
let rightCup = CGRect(x: cx + bandR - cupW / 2, y: cupMinCG,
                      width: cupW, height: cupH)

ctx.addPath(CGPath(roundedRect: leftCup,  cornerWidth: cupR, cornerHeight: cupR, transform: nil))
ctx.fillPath()
ctx.addPath(CGPath(roundedRect: rightCup, cornerWidth: cupR, cornerHeight: cupR, transform: nil))
ctx.fillPath()

// ── 3. Export ─────────────────────────────────────────────────────────────
let cgImg = ctx.makeImage()!
let rep   = NSBitmapImageRep(cgImage: cgImg)
let data  = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: "soundlock_1024.png"))
print("✅  soundlock_1024.png saved")
