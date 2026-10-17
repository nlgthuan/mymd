// Turns a window snapshot PDF (from MYMD_SNAPSHOT) into a README screenshot:
// rasterised at 2x with macOS-style rounded corners, hairline border and shadow.
// Usage: swift tools/frame-shot.swift in.pdf out.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let doc = CGPDFDocument(URL(fileURLWithPath: args[1]) as CFURL), let page = doc.page(at: 1) else {
    FileHandle.standardError.write("usage: frame-shot in.pdf out.png\n".data(using: .utf8)!)
    exit(1)
}

let scale: CGFloat = 2
// Just enough room for the shadow, which falls downward: tight at the top so the
// image doesn't leave a big gap under the text above it in the README.
let pad = (top: CGFloat(6), side: CGFloat(20), bottom: CGFloat(30))
let radius: CGFloat = 12
let box = page.getBoxRect(.mediaBox)
let size = CGSize(width: box.width + 2 * pad.side, height: box.height + pad.top + pad.bottom)

let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)

let frame = CGRect(x: pad.side, y: pad.bottom, width: box.width, height: box.height)
let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Shadow: draw the window shape once with a soft, slightly offset shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Content, clipped to the rounded window.
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.translateBy(x: pad.side - box.minX, y: pad.bottom - box.minY)
ctx.drawPDFPage(page)
ctx.restoreGState()

// Hairline border, as macOS draws around windows.
ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.22))
ctx.setLineWidth(0.5)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = size  // 144 dpi, so it displays at 1x size on GitHub-style renderers
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
