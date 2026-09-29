//
//  make_gif.swift
//  tools/dev
//
//  A screen recording -> an animated GIF, with nothing installed:
//
//      swift tools/dev/make_gif.swift <video> <out.gif> [fps] [width] [start] [end] [hold]
//
//  fps defaults to 8, width to 360 points (the height follows the video), and
//  start/end (seconds) trim the recording. hold (seconds) shows a stretch where
//  nothing moves as one frame for at most that long, so the pauses between
//  gestures drop out of the GIF; without it every frame is kept. Record the
//  simulator with `xcrun simctl io <udid> recordVideo --codec h264 <video>`;
//  the GIF goes in docs/media/ for the README.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make_gif.swift <video> <out.gif> [fps] [width] [start] [end] [hold]\n".utf8))
    exit(2)
}
let videoURL = URL(fileURLWithPath: arguments[1])
let gifURL = URL(fileURLWithPath: arguments[2])
let fps = arguments.count > 3 ? Double(arguments[3]) ?? 8 : 8
let width = arguments.count > 4 ? Double(arguments[4]) ?? 360 : 360
let start = arguments.count > 5 ? Double(arguments[5]) ?? 0 : 0
let asset = AVURLAsset(url: videoURL)
let duration = CMTimeGetSeconds(asset.duration)
let end = arguments.count > 6 ? min(Double(arguments[6]) ?? duration, duration) : duration
let hold = arguments.count > 7 ? Double(arguments[7]) : nil
guard end > start else {
    FileHandle.standardError.write(Data("nothing to do: the clip is \(duration)s\n".utf8))
    exit(1)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: width, height: 0)   // the height follows

func frame(at seconds: Double) -> CGImage? {
    do {
        return try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
    } catch {
        FileHandle.standardError.write(Data("frame at \(seconds)s: \(error.localizedDescription)\n".utf8))
        return nil
    }
}

/// A small grey copy of a frame, enough to tell a still stretch from movement.
func thumbnail(_ image: CGImage) -> [UInt8] {
    let w = 100, h = max(1, image.height * 100 / max(1, image.width))
    var pixels = [UInt8](repeating: 0, count: w * h)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return pixels
}

/// No pixel moved by more than the video's compression noise.
func isStill(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    a.count == b.count && !zip(a, b).contains { abs(Int($0) - Int($1)) > 24 }
}

// The frames to write and how long each shows. With a hold, a frame that looks
// like the last one kept lengthens that one instead, up to the hold.
let step = 1.0 / fps
var frames: [(seconds: Double, delay: Double)] = []
var lastKept: [UInt8]?
for index in 0..<Int((end - start) * fps) {
    let seconds = start + Double(index) * step
    if let hold {
        guard let image = frame(at: seconds) else { continue }
        let small = thumbnail(image)
        if let lastKept, isStill(lastKept, small), !frames.isEmpty {
            frames[frames.count - 1].delay = min(frames[frames.count - 1].delay + step, max(hold, step))
            continue
        }
        lastKept = small
    }
    frames.append((seconds, step))
}

guard !frames.isEmpty,
      let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString,
                                                        frames.count, nil) else {
    FileHandle.standardError.write(Data("cannot write \(gifURL.path)\n".utf8))
    exit(1)
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

var written = 0
var length = 0.0
for (seconds, delay) in frames {
    guard let image = frame(at: seconds) else { continue }
    let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    written += 1
    length += delay
}
guard CGImageDestinationFinalize(destination), written > 0 else {
    FileHandle.standardError.write(Data("the GIF was not written\n".utf8))
    exit(1)
}
let size = (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int) ?? 0
print("\(written) frames, \(String(format: "%.1f", length)) s, \(String(format: "%.1f", Double(size ?? 0) / 1_048_576)) MB -> \(gifURL.path)")
