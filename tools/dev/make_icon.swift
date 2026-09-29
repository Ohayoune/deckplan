// make_icon.swift — draws DeckPlan's app icon with CoreGraphics (DECISIONS_LOG
// 2026-09-13, "The app icon") and writes the three 1024 × 1024 PNGs the asset
// catalog lists: AppIcon.png (opaque, pool-blue ground), AppIcon-Dark.png and
// AppIcon-Tinted.png (transparent grounds: iOS draws its own dark ground behind
// them, and tints the grayscale one).
//
//     swift tools/dev/make_icon.swift [output directory]
//
// The output directory defaults to DeckPlan/Assets.xcassets/AppIcon.appiconset.
// The picture: a deck of two plan cards on pool water. The front card carries
// the day's timeline (three dots on a rail, each with its line, as a class day
// is drawn) above a band of water.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, alpha])!
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [white, white, white, alpha])!
}

struct Palette {
    /// Top-left to bottom-right; nil leaves the ground transparent.
    var ground: (CGColor, CGColor)?
    var glow: CGColor?
    var backCard: CGColor
    var frontCard: CGColor
    var shadow: CGColor
    var rail: CGColor
    var dot: CGColor
    var bar: CGColor
    var farWave: CGColor
    var nearWave: (CGColor, CGColor)
}

let light = Palette(ground: (rgb(0x35B6E6), rgb(0x0C4A8A)), glow: gray(1, 0.22),
                    backCard: gray(1, 0.30), frontCard: gray(1), shadow: rgb(0x031D3D, 0.40),
                    rail: rgb(0xBFD9EC), dot: rgb(0x1B6FAD), bar: rgb(0xDCEAF5),
                    farWave: rgb(0x9FD9F2), nearWave: (rgb(0x3BB5E8), rgb(0x1B6FAD)))
let dark = Palette(ground: nil, glow: nil,
                   backCard: rgb(0x4AABE1, 0.30), frontCard: rgb(0xEAF4FB), shadow: gray(0, 0.55),
                   rail: rgb(0xA9CDE6), dot: rgb(0x1B6FAD), bar: rgb(0xCFE2F1),
                   farWave: rgb(0x8ED0F0), nearWave: (rgb(0x4AABE1), rgb(0x1B6FAD)))
let tinted = Palette(ground: nil, glow: nil,
                     backCard: gray(1, 0.35), frontCard: gray(1), shadow: gray(0, 0.5),
                     rail: gray(0.72), dot: gray(0.30), bar: gray(0.85),
                     farWave: gray(0.70), nearWave: (gray(0.55), gray(0.32)))

let cardSize = CGSize(width: 500, height: 600)
let cardRadius: CGFloat = 76

func cardPath() -> CGPath {
    CGPath(roundedRect: CGRect(x: -cardSize.width / 2, y: -cardSize.height / 2,
                               width: cardSize.width, height: cardSize.height),
           cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
}

/// A wave's filled area in card space: its crest line at `base`, down past the card's foot.
func wave(base: CGFloat, amplitude: CGFloat, length: CGFloat, phase: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let left = -cardSize.width / 2 - 10, right = cardSize.width / 2 + 10, foot = cardSize.height / 2 + 10
    path.move(to: CGPoint(x: left, y: foot))
    var x = left
    while x <= right {
        path.addLine(to: CGPoint(x: x, y: base + amplitude * sin(2 * .pi * x / length + phase)))
        x += 2
    }
    path.addLine(to: CGPoint(x: right, y: foot))
    path.closeSubpath()
    return path
}

func draw(_ palette: Palette, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: info.rawValue)!
    let s = CGFloat(side)
    // y down, as the design is laid out
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    if let (top, bottom) = palette.ground {
        let ground = CGGradient(colorsSpace: srgb, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(ground, start: CGPoint(x: s * 0.15, y: 0), end: CGPoint(x: s * 0.85, y: s),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    if let glow = palette.glow {
        let clear = glow.copy(alpha: 0)!
        let light = CGGradient(colorsSpace: srgb, colors: [glow, clear] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(light, startCenter: CGPoint(x: 250, y: 150), startRadius: 0,
                               endCenter: CGPoint(x: 250, y: 150), endRadius: 720, options: [])
    }

    // the back card, leaning right
    ctx.saveGState()
    ctx.translateBy(x: 552, y: 470)
    ctx.rotate(by: 9 * .pi / 180)
    ctx.addPath(cardPath())
    ctx.setFillColor(palette.backCard)
    ctx.fillPath()
    ctx.restoreGState()

    // the front card, leaning left, with its shadow (offsets are in device space: y up)
    ctx.saveGState()
    ctx.translateBy(x: 470, y: 548)
    ctx.rotate(by: -5 * .pi / 180)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 64, color: palette.shadow)
    ctx.addPath(cardPath())
    ctx.setFillColor(palette.frontCard)
    ctx.fillPath()
    ctx.restoreGState()

    // the timeline: a rail, three dots, a line of text beside each
    let railX: CGFloat = -150
    let rows: [(y: CGFloat, length: CGFloat)] = [(-192, 250), (-106, 196), (-20, 226)]
    ctx.setStrokeColor(palette.rail)
    ctx.setLineWidth(12)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: railX, y: rows[0].y))
    ctx.addLine(to: CGPoint(x: railX, y: rows[2].y))
    ctx.strokePath()
    for row in rows {
        ctx.setFillColor(palette.dot)
        ctx.fillEllipse(in: CGRect(x: railX - 25, y: row.y - 25, width: 50, height: 50))
        ctx.setFillColor(palette.bar)
        ctx.addPath(CGPath(roundedRect: CGRect(x: -96, y: row.y - 21, width: row.length, height: 42),
                           cornerWidth: 21, cornerHeight: 21, transform: nil))
        ctx.fillPath()
    }

    // the water, inside the card
    ctx.addPath(cardPath())
    ctx.clip()
    ctx.addPath(wave(base: 78, amplitude: 20, length: 340, phase: 2.2))
    ctx.setFillColor(palette.farWave)
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(wave(base: 122, amplitude: 26, length: 380, phase: 0.4))
    ctx.clip()
    let (near, deep) = palette.nearWave
    let water = CGGradient(colorsSpace: srgb, colors: [near, deep] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(water, start: CGPoint(x: 0, y: 90), end: CGPoint(x: 0, y: 300), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write("Could not write \(url.path)\n".data(using: .utf8)!)
        exit(1)
    }
    print("wrote \(url.path)")
}

let arguments = CommandLine.arguments.dropFirst()
let output = URL(fileURLWithPath: arguments.first ?? "DeckPlan/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
write(draw(light, opaque: true), to: output.appendingPathComponent("AppIcon.png"))
write(draw(dark, opaque: false), to: output.appendingPathComponent("AppIcon-Dark.png"))
write(draw(tinted, opaque: false), to: output.appendingPathComponent("AppIcon-Tinted.png"))
