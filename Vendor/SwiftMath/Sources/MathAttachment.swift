// mymd: small entry point into SwiftMath's typesetter that also reports the
// descent, so inline formulas can sit on the text baseline.
import AppKit

public struct RenderedMath {
    public let image: NSImage
    public let descent: CGFloat
}

public enum MathRenderer {
    /// Typesets `latex` at `size` points. `display` selects display style
    /// (big operators, stacked limits) versus inline text style.
    public static func render(_ latex: String, size: CGFloat, color: NSColor, display: Bool) -> Result<RenderedMath, Error> {
        var error: NSError?
        guard let font = MTFontManager.fontManager.latinModernFont(withSize: size) else {
            return .failure(NSError(domain: "mymd", code: 1, userInfo: [NSLocalizedDescriptionKey: "math font unavailable"]))
        }
        guard let list = MTMathListBuilder.build(fromString: latex, error: &error), error == nil,
              let line = MTTypesetter.createLineForMathList(list, font: font, style: display ? .display : .text) else {
            return .failure(error ?? NSError(domain: "mymd", code: 2, userInfo: [NSLocalizedDescriptionKey: "invalid math"]))
        }
        line.textColor = color
        let pad: CGFloat = 1
        let size = CGSize(width: ceil(line.width) + 2 * pad, height: ceil(line.ascent + line.descent) + 2 * pad)
        line.position = CGPoint(x: pad, y: line.descent + pad)
        // Rasterise up front at 2x: a lazy drawing handler would be invoked in the
        // text view's flipped context and come out upside down.
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return .failure(NSError(domain: "mymd", code: 3, userInfo: [NSLocalizedDescriptionKey: "bitmap failed"]))
        }
        ctx.scaleBy(x: scale, y: scale)
        // Some displays (radical bars) stroke via NSGraphicsContext.current, and
        // SwiftMath doesn't propagate textColor to every glyph (the radical sign).
        // Draw with our context current, then paint all ink in one colour.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        line.draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        guard let cg = ctx.makeImage() else {
            return .failure(NSError(domain: "mymd", code: 3, userInfo: [NSLocalizedDescriptionKey: "bitmap failed"]))
        }
        let image = NSImage(cgImage: cg, size: size)
        return .success(RenderedMath(image: image, descent: line.descent + pad))
    }
}
