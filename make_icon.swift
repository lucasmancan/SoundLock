#!/usr/bin/swift
// Generates soundlock_1024.png
// Vintage condenser mic silhouette + padlock badge overlapping lower-right.
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

// ── 1. Squircle background ────────────────────────────────────────────────
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                    cornerWidth: 224, cornerHeight: 224, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

let grad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(srgbRed: 0.20, green: 0.42, blue: 0.94, alpha: 1),  // blue  (top-left)
        CGColor(srgbRed: 0.44, green: 0.22, blue: 0.84, alpha: 1),  // purple (bottom-right)
    ] as CFArray,
    locations: [0, 1])!
// In CG Y-up: (0, size) = top-left, (size, 0) = bottom-right
ctx.drawLinearGradient(grad,
    start: CGPoint(x: 0,    y: size),
    end:   CGPoint(x: size, y: 0),
    options: [])
ctx.resetClip()

let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
ctx.setFillColor(white)

// ── 2. Microphone ─────────────────────────────────────────────────────────
// Mic is left-of-centre; lock badge will overlap its lower-right corner.
let micCx: CGFloat = 420

// 2a. Capsule — narrow tall oval (not a circle).
//     Grille lines only in top ~55 %; solid white below.
let capCY:  CGFloat = 672    // CG Y centre (appears near top of displayed icon)
let capW:   CGFloat = 192    // narrow
let capH:   CGFloat = 312    // tall → elongated capsule
let capCR:  CGFloat = capW / 2

let capTopCG    = capCY + capH / 2   // ≈ 828 — displayed top
let capBottomCG = capCY - capH / 2   // ≈ 516 — displayed bottom

let capRect = CGRect(x: micCx - capW / 2, y: capBottomCG, width: capW, height: capH)
let capPath = CGPath(roundedRect: capRect, cornerWidth: capCR, cornerHeight: capCR,
                     transform: nil)

// Fill capsule solid white
ctx.addPath(capPath)
ctx.fillPath()

// Grille cuts — clip to capsule, draw 4 dark horizontal bands in the top 55 %
ctx.saveGState()
ctx.addPath(capPath)
ctx.clip()

let grilleColor = CGColor(srgbRed: 0.28, green: 0.18, blue: 0.80, alpha: 0.82)
ctx.setFillColor(grilleColor)

let slotH: CGFloat  = 16     // each dark slot
let pitch: CGFloat  = 40     // slot + white gap
let nSlots          = 4
// First slot top sits ~48 px below the capsule's very top arc
let grillFirstTop = capTopCG - 48

for i in 0 ..< nSlots {
    let slotTopCG = grillFirstTop - CGFloat(i) * pitch
    ctx.fill(CGRect(x: micCx - capW / 2, y: slotTopCG - slotH,
                    width: capW, height: slotH))
}
ctx.restoreGState()

// 2b. Neck — thin connector below capsule
let neckW: CGFloat = 36
let neckH: CGFloat = 80
let neckMinCG = capBottomCG - neckH   // ≈ 436
ctx.setFillColor(white)
ctx.addPath(CGPath(roundedRect: CGRect(x: micCx - neckW / 2, y: neckMinCG,
                                       width: neckW, height: neckH),
                   cornerWidth: 11, cornerHeight: 11, transform: nil))
ctx.fillPath()

// 2c. Base — wide rounded platform
let baseW: CGFloat = 248
let baseH: CGFloat = 52
// Slight overlap with neck bottom for a clean join
let baseMinCG = neckMinCG - baseH + 6   // ≈ 390
ctx.addPath(CGPath(roundedRect: CGRect(x: micCx - baseW / 2, y: baseMinCG,
                                       width: baseW, height: baseH),
                   cornerWidth: 26, cornerHeight: 26, transform: nil))
ctx.fillPath()

// ── 3. Padlock badge — overlapping lower-right corner of the mic ──────────
// lkCx is right of micCx so the lock overlaps the mic's base/neck area.
let lkCx:      CGFloat = 576
let bodyW:     CGFloat = 150
let bodyH:     CGFloat = 126
// bodyMaxY = displayed top of lock body; aligns with the neck/base junction area
let bodyMaxCG: CGFloat = 458
let bodyMinCG  = bodyMaxCG - bodyH        // ≈ 332

// 3a. Shackle — thick arc above the body; clockwise:false = ∩ in CG Y-up
let shR:  CGFloat = 42    // arch radius
let shLW: CGFloat = 42    // stroke width (looks solid)
ctx.setStrokeColor(white)
ctx.setLineWidth(shLW)
ctx.setLineCap(.butt)

let shPath = CGMutablePath()
shPath.addArc(center: CGPoint(x: lkCx, y: bodyMaxCG),
              radius: shR, startAngle: 0, endAngle: .pi, clockwise: false)
ctx.addPath(shPath)
ctx.strokePath()

// 3b. Lock body — fill after shackle to cover butt-cap stubs
ctx.setFillColor(white)
ctx.addPath(CGPath(roundedRect: CGRect(x: lkCx - bodyW / 2, y: bodyMinCG,
                                       width: bodyW, height: bodyH),
                   cornerWidth: 20, cornerHeight: 20, transform: nil))
ctx.fillPath()

// 3c. Keyhole (circle + slot) in background colour
let khColor = CGColor(srgbRed: 0.30, green: 0.18, blue: 0.82, alpha: 1)
ctx.setFillColor(khColor)
let khR:  CGFloat = 17
// 40 % from displayed top = bodyMaxCG - 0.40 * bodyH
let khCY  = bodyMaxCG - bodyH * 0.40      // ≈ 408
ctx.addPath(CGPath(ellipseIn: CGRect(x: lkCx - khR, y: khCY - khR,
                                     width: khR * 2, height: khR * 2), transform: nil))
ctx.fillPath()
// Slot directly below circle (lower CG Y = lower in displayed image)
ctx.fill(CGRect(x: lkCx - 9, y: khCY - khR - 22, width: 18, height: 22))

// ── 4. Export ─────────────────────────────────────────────────────────────
let cgImg = ctx.makeImage()!
let rep   = NSBitmapImageRep(cgImage: cgImg)
let data  = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: "soundlock_1024.png"))
print("✅  soundlock_1024.png saved")
