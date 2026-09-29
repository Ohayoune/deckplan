// Render PDF pages to PNG with PDFKit, so a page can be read visually.
// Dev aid for M1 transcription and M9 form layout; macOS only.
//
// usage: swift tools/dev/render_pdf_page.swift FILE.pdf OUT_PREFIX PAGE [PAGE...] [--scale N]
//    or: swiftc -O tools/dev/render_pdf_page.swift -o <bin>  (then run <bin> with the same arguments)
// Writes OUT_PREFIX-p<PAGE>.png for each 1-based PAGE. Default scale 2 (144 dpi).
// Renders of toolkit pages are YMCA content: write them under curriculum/ or a scratch folder, never commit them.

import AppKit
import Foundation
import PDFKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
var scale = 2.0
if let i = args.firstIndex(of: "--scale") {
    guard i + 1 < args.count, let value = Double(args[i + 1]), value > 0 else { fail("--scale needs a positive number") }
    scale = value
    args.removeSubrange(i...(i + 1))
}
guard args.count >= 3 else {
    fail("usage: render_pdf_page FILE.pdf OUT_PREFIX PAGE [PAGE...] [--scale N]")
}
guard let document = PDFDocument(url: URL(fileURLWithPath: args[0])) else { fail("cannot open \(args[0])") }

for pageArg in args[2...] {
    guard let number = Int(pageArg), let page = document.page(at: number - 1) else {
        fail("no page \(pageArg) in \(args[0]) (\(document.pageCount) pages)")
    }
    let box = page.bounds(for: .mediaBox)
    let quarterTurns = ((page.rotation % 360) + 360) % 360 / 90
    let size = quarterTurns % 2 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { fail("cannot make a bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
    cg.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: cg)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode PNG") }
    let out = "\(args[1])-p\(number).png"
    do { try png.write(to: URL(fileURLWithPath: out)) } catch { fail("cannot write \(out): \(error)") }
    print("\(out) \(width)x\(height)")
}
