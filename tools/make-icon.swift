// Renders the app icon: a dark squircle with the markdown "M↓" mark.
// Usage: swift tools/make-icon.swift <out.iconset>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt body inset 100pt, continuous-corner radius ~185.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x1f2023))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [rgb(0x34363b), rgb(0x18191c)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // faint top highlight
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
    ctx.setLineWidth(4)
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.strokePath()
    ctx.restoreGState()

    // Markdown mark (from the 208x128 reference glyph), centered and flipped to CG coords.
    let k: CGFloat = 3.5
    let gw: CGFloat = 155 * k, gh: CGFloat = 68 * k
    let ox = 512 - gw / 2 - 30 * k, oy = 512 + gh / 2 + 30 * k
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * k, y: oy - y * k) }

    let m = CGMutablePath()
    m.move(to: p(30, 98)); m.addLine(to: p(30, 30)); m.addLine(to: p(50, 30)); m.addLine(to: p(70, 55))
    m.addLine(to: p(90, 30)); m.addLine(to: p(110, 30)); m.addLine(to: p(110, 98)); m.addLine(to: p(90, 98))
    m.addLine(to: p(90, 59)); m.addLine(to: p(70, 84)); m.addLine(to: p(50, 59)); m.addLine(to: p(50, 98))
    m.closeSubpath()
    ctx.addPath(m)
    ctx.setFillColor(rgb(0xf2f1ec))
    ctx.fillPath()

    let a = CGMutablePath()
    a.move(to: p(155, 98)); a.addLine(to: p(125, 65)); a.addLine(to: p(145, 65)); a.addLine(to: p(145, 30))
    a.addLine(to: p(165, 30)); a.addLine(to: p(165, 65)); a.addLine(to: p(185, 65))
    a.closeSubpath()
    ctx.addPath(a)
    ctx.setFillColor(rgb(0x6ea5ff))
    ctx.fillPath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! render(size * scale).write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
