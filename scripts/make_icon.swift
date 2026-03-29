#!/usr/bin/swift
/// Generates the 1024×1024 master PNG for PostureReminder's app icon.
/// Run:  swift scripts/make_icon.swift [output.png]
///
/// Design:
///   • Deep indigo background with diagonal gradient
///   • Subtle inner glow behind the figure
///   • White seated-person silhouette (head + torso + legs + arm)
///   • Amber progress arc suggesting a countdown timer
///   • Small amber clock badge (bottom-right)

import AppKit
import ImageIO

// ── Canvas ────────────────────────────────────────────────────────────────────
let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S),
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fputs("Cannot create context\n", stderr); exit(1) }

// Helper: fill rounded rect
func fillRounded(_ r: CGRect, _ rad: CGFloat) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
    ctx.fillPath()
}

// ── 1. Clip to rounded rect (macOS icon shape) ────────────────────────────────
let cornerR: CGFloat = S * 0.225
ctx.addPath(CGPath(roundedRect: CGRect(x:0, y:0, width:S, height:S),
                   cornerWidth: cornerR, cornerHeight: cornerR, transform: nil))
ctx.clip()

// ── 2. Gradient background ────────────────────────────────────────────────────
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.09, green: 0.06, blue: 0.28, alpha: 1),   // dark indigo (bottom-left)
    CGColor(srgbRed: 0.22, green: 0.14, blue: 0.52, alpha: 1),   // medium purple (top-right)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad,
    start: CGPoint(x: 0, y: 0), end: CGPoint(x: S, y: S),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// ── 3. Soft inner glow ────────────────────────────────────────────────────────
let glow = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.50, green: 0.38, blue: 0.90, alpha: 0.22),
    CGColor(srgbRed: 0.50, green: 0.38, blue: 0.90, alpha: 0.00),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow,
    startCenter: CGPoint(x: S*0.46, y: S*0.52), startRadius: 0,
    endCenter:   CGPoint(x: S*0.46, y: S*0.52), endRadius: S*0.50,
    options: [])

// ── 4. Timer ring ─────────────────────────────────────────────────────────────
let ringCX: CGFloat = S * 0.50
let ringCY: CGFloat = S * 0.48
let ringR:  CGFloat = S * 0.365
let ringW:  CGFloat = S * 0.046

ctx.setLineWidth(ringW)
ctx.setLineCap(.round)

// Dim full ring
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
ctx.addEllipse(in: CGRect(x: ringCX-ringR, y: ringCY-ringR,
                           width: ringR*2, height: ringR*2))
ctx.strokePath()

// ~75% amber arc
ctx.setStrokeColor(CGColor(srgbRed: 1.00, green: 0.74, blue: 0.20, alpha: 0.88))
ctx.beginPath()
ctx.addArc(center: CGPoint(x: ringCX, y: ringCY), radius: ringR,
           startAngle:  .pi * 0.5,
           endAngle:    .pi * 0.5 - .pi * 2 * 0.75,
           clockwise:   true)
ctx.strokePath()

// ── 5. Seated person figure ───────────────────────────────────────────────────
//  CGContext: origin = bottom-left, Y increases upward.
//  Person faces RIGHT:  arm extends right, legs extend left.
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.94))

// Head
let hR:  CGFloat = S * 0.085
let hCX: CGFloat = S * 0.440
let hCY: CGFloat = S * 0.610
ctx.addEllipse(in: CGRect(x: hCX-hR, y: hCY-hR, width: hR*2, height: hR*2))
ctx.fillPath()

// Torso (below head)
let tW: CGFloat = S * 0.098, tH: CGFloat = S * 0.192
let tX = hCX - tW/2, tY = hCY - hR - tH
fillRounded(CGRect(x: tX, y: tY, width: tW, height: tH), tW * 0.40)

// Upper leg (horizontal, extends left from hip)
let ulW: CGFloat = S * 0.205, ulH: CGFloat = S * 0.062
let ulY = tY - ulH * 0.18
let ulX = tX - ulW + tW * 0.65
fillRounded(CGRect(x: ulX, y: ulY, width: ulW, height: ulH), ulH * 0.46)

// Lower leg (vertical, hangs from knee)
let llW: CGFloat = S * 0.056, llH: CGFloat = S * 0.148
let llX = ulX - llW * 0.05
let llY = ulY - llH + ulH * 0.12
fillRounded(CGRect(x: llX, y: llY, width: llW, height: llH), llW * 0.46)

// Arm (extends right — reaching toward monitor)
let aW: CGFloat = S * 0.055, aH: CGFloat = S * 0.142
let aX = hCX + tW * 0.30
let aY = tY + tH * 0.64 - aW / 2
fillRounded(CGRect(x: aX, y: aY, width: aH, height: aW), aW * 0.46)

// ── 6. Clock badge (bottom-right) ─────────────────────────────────────────────
let bR:  CGFloat = S * 0.082
let bCX: CGFloat = S * 0.678
let bCY: CGFloat = S * 0.175

// Amber filled circle
ctx.setFillColor(CGColor(srgbRed: 1.00, green: 0.74, blue: 0.20, alpha: 1.0))
ctx.addEllipse(in: CGRect(x: bCX-bR, y: bCY-bR, width: bR*2, height: bR*2))
ctx.fillPath()

// Clock hands (dark)
let handColor = CGColor(srgbRed: 0.10, green: 0.07, blue: 0.28, alpha: 1)
ctx.setStrokeColor(handColor)
ctx.setLineWidth(S * 0.011)
ctx.setLineCap(.round)
// Hour hand (pointing ~10 o'clock)
ctx.move(to: CGPoint(x: bCX, y: bCY))
ctx.addLine(to: CGPoint(x: bCX - bR*0.40, y: bCY + bR*0.38))
ctx.strokePath()
// Minute hand (pointing ~12 o'clock)
ctx.move(to: CGPoint(x: bCX, y: bCY))
ctx.addLine(to: CGPoint(x: bCX, y: bCY + bR*0.56))
ctx.strokePath()
// Center dot
ctx.setFillColor(handColor)
let dR: CGFloat = S * 0.009
ctx.addEllipse(in: CGRect(x: bCX-dR, y: bCY-dR, width: dR*2, height: dR*2))
ctx.fillPath()

// ── 7. Export PNG ─────────────────────────────────────────────────────────────
guard let cgImage = ctx.makeImage() else {
    fputs("makeImage failed\n", stderr); exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon_1024.png"
let outURL  = URL(fileURLWithPath: outPath)

guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("Cannot create image destination\n", stderr); exit(1)
}
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Finalize failed\n", stderr); exit(1)
}

print("✓ Icon saved → \(outPath)")
