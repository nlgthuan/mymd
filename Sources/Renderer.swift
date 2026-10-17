import AppKit

// Markdown -> NSAttributedString, using Foundation's (cmark-gfm based) parser and
// TextKit 1 text blocks/tables for block-level layout.

enum Palette {
    static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
    static let bg = dyn(rgb(252, 252, 250), rgb(28, 28, 30))
    static let text = dyn(rgb(36, 36, 38), rgb(218, 218, 214))
    static let muted = dyn(rgb(110, 110, 115), rgb(140, 140, 145))
    static let codeBg = dyn(rgb(242, 242, 240), rgb(40, 40, 43))
    static let rule = dyn(rgb(222, 222, 220), rgb(62, 62, 66))
    static let link = dyn(rgb(10, 95, 200), rgb(110, 165, 255))
    static let bar = dyn(rgb(244, 244, 242), rgb(22, 22, 24))
    static let hint = rgb(255, 214, 80)
    static let error = dyn(rgb(190, 40, 40), rgb(255, 110, 100))
}

final class ImageRef {
    var attachment: NSTextAttachment
    let url: URL
    let width: CGFloat?
    let alt: String
    var image: NSImage?
    init(attachment: NSTextAttachment, url: URL, width: CGFloat?, alt: String) {
        self.attachment = attachment; self.url = url; self.width = width; self.alt = alt
    }
}

enum ImageCache {
    static var images: [URL: NSImage] = [:]
}

final class Renderer {
    let base: URL
    let size: CGFloat
    private(set) var anchors: [String: Int] = [:]
    private(set) var images: [ImageRef] = []

    private let out = NSMutableAttributedString()
    private var seenItems = Set<Int>()
    private var quoteBlocks: [Int: NSTextBlock] = [:]
    private var prevInList = false
    private var slugCounts: [String: Int] = [:]
    private var table: TableState?
    private var h = HTMLState()
    private var step: CGFloat { size * 1.7 }

    private struct TableState {
        let id: Int
        let table: NSTextTable
        let aligns: [NSTextAlignment]
        let outer: [NSTextBlock]
        var row = -1, rowID = -1, nextCol = 0
        var header = false
    }

    private struct HTMLState {
        var bold = 0, italic = 0, code = 0, strike = 0, sup = 0, sub = 0, heading = 0
        var link: URL?
        var centerStack: [String] = []
        var centeredBlock = false
    }

    init(base: URL, size: CGFloat) {
        self.base = base
        self.size = size
    }

    // MARK: fonts

    private var fontCache: [String: NSFont] = [:]
    private lazy var body: NSFont = .systemFont(ofSize: size)
    private func mono(_ s: CGFloat, bold: Bool = false) -> NSFont {
        .monospacedSystemFont(ofSize: s, weight: bold ? .semibold : .regular)
    }
    private func headingFont(_ level: Int) -> NSFont {
        let scale: [CGFloat] = [2.0, 1.55, 1.27, 1.1, 1.0, 0.92]
        return .systemFont(ofSize: size * scale[min(max(level, 1), 6) - 1], weight: level <= 2 ? .bold : .semibold)
    }
    private func blockFont(_ intent: PresentationIntent?) -> NSFont {
        switch intent?.components.first?.kind {
        case .header(let l)?: return headingFont(l)
        case .codeBlock?: return mono(size * 0.86)
        default: return body
        }
    }

    // MARK: entry

    func render(_ source: String) -> NSAttributedString {
        let md = preprocess(source)
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let doc = try? AttributedString(markdown: md, options: opts) else {
            return NSAttributedString(string: source, attributes: [.font: mono(size * 0.9), .foregroundColor: Palette.text])
        }
        var buf = NSMutableAttributedString()
        var curID: Int?
        var curIntent: PresentationIntent?
        for run in doc.runs {
            let intent = run.presentationIntent
            let ipi = run.inlinePresentationIntent ?? []
            let id = intent?.components.first?.identity ?? -1
            if let c = curID, c != id || id == -1 {
                flush(curIntent, buf)
                buf = NSMutableAttributedString()
            }
            curID = id
            curIntent = intent
            let text = String(doc[run.range].characters)
            let font = blockFont(intent)
            if ipi.contains(.inlineHTML) || ipi.contains(.blockHTML) {
                appendHTML(text, to: buf, font: font)
            } else if ipi.contains(.softBreak) {
                buf.append(styled(" ", font: font))
            } else if ipi.contains(.lineBreak) {
                buf.append(styled("\u{2028}", font: font))
            } else if let img = run.imageURL {
                buf.append(image(img.absoluteString, alt: text, width: nil, font: font, link: run.link))
            } else {
                buf.append(styled(text, font: font, ipi: ipi, link: run.link))
            }
        }
        if curID != nil { flush(curIntent, buf) }
        finishTable()
        return out
    }

    // MARK: inline

    private func styled(_ s: String, font base: NSFont, ipi: InlinePresentationIntent = [],
                        link: URL? = nil, color: NSColor = Palette.text) -> NSAttributedString {
        var font = h.heading > 0 ? headingFont(h.heading) : base
        let code = ipi.contains(.code) || h.code > 0
        let bold = ipi.contains(.stronglyEmphasized) || h.bold > 0
        let italic = ipi.contains(.emphasized) || h.italic > 0
        let fm = NSFontManager.shared
        if code {
            font = mono(font.pointSize * 0.88, bold: bold)
        } else if bold || italic {
            let key = "\(font.fontName)|\(font.pointSize)|\(bold)|\(italic)"
            if let f = fontCache[key] {
                font = f
            } else {
                if bold { font = fm.convert(font, toHaveTrait: .boldFontMask) }
                if italic { font = fm.convert(font, toHaveTrait: .italicFontMask) }
                fontCache[key] = font
            }
        }
        var a: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        if h.sup > 0 || h.sub > 0 {
            font = fm.convert(font, toSize: font.pointSize * 0.75)
            a[.baselineOffset] = h.sup > 0 ? size * 0.35 : -size * 0.15
        }
        a[.font] = font
        if code { a[.backgroundColor] = Palette.codeBg }
        if ipi.contains(.strikethrough) || h.strike > 0 { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let l = link ?? h.link { a[.link] = l; a[.foregroundColor] = Palette.link }
        return NSAttributedString(string: s, attributes: a)
    }

    func resolve(_ s: String) -> URL? {
        if let u = URL(string: s), u.scheme != nil { return u }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
        let enc = s.removingPercentEncoding ?? s
        return URL(fileURLWithPath: enc, relativeTo: base).absoluteURL
    }

    static func fit(_ img: NSImage, width pref: CGFloat?, max maxW: CGFloat) -> CGRect {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return .zero }
        let w = min(pref ?? s.width, max(maxW, 40))
        let h = s.height * w / s.width
        return CGRect(x: 0, y: h < 32 ? -4 : 0, width: w, height: h)
    }

    private func image(_ src: String, alt: String, width: CGFloat?, font: NSFont, link: URL?) -> NSAttributedString {
        guard let u = resolve(src) else { return styled(alt, font: font) }
        let att = NSTextAttachment()
        let ref = ImageRef(attachment: att, url: u, width: width, alt: alt)
        if let img = ImageCache.images[u] {
            att.image = img
            att.bounds = Renderer.fit(img, width: width, max: size * 50)
            ref.image = img
        } else {
            att.image = NSImage(size: NSSize(width: 1, height: 1))
            att.bounds = .zero
        }
        images.append(ref)
        let s = NSMutableAttributedString(attachment: att)
        var a: [NSAttributedString.Key: Any] = [.font: font]
        if !alt.isEmpty { a[.toolTip] = alt }
        if let l = link ?? h.link { a[.link] = l }
        s.addAttributes(a, range: NSRange(location: 0, length: s.length))
        return s
    }

    // MARK: html (the common README subset)

    private static let tokRe = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->|</?[A-Za-z][^>]*>|[^<]+|<")
    private static let attrRe = try! NSRegularExpression(
        pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))")

    private func appendHTML(_ s: String, to buf: NSMutableAttributedString, font: NSFont) {
        let ns = s as NSString
        for m in Self.tokRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let tok = ns.substring(with: m.range)
            if tok.hasPrefix("<!--") { continue }
            if tok.count > 1 && tok.hasPrefix("<") { tag(tok, buf, font); continue }
            var text = decodeEntities(tok.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression))
            if buf.length == 0 || buf.string.hasSuffix("\u{2028}") {
                text = String(text.drop { $0 == " " })
            }
            if !text.isEmpty { buf.append(styled(text, font: font)) }
        }
    }

    private func tag(_ tok: String, _ buf: NSMutableAttributedString, _ font: NSFont) {
        let closing = tok.hasPrefix("</")
        let name = String(tok.dropFirst(closing ? 2 : 1).prefix { $0.isLetter || $0.isNumber }).lowercased()
        var attrs: [String: String] = [:]
        if !closing {
            let ns = tok as NSString
            for m in Self.attrRe.matches(in: tok, range: NSRange(location: 0, length: ns.length)) {
                let key = ns.substring(with: m.range(at: 1)).lowercased()
                for g in 2...4 where m.range(at: g).location != NSNotFound {
                    attrs[key] = decodeEntities(ns.substring(with: m.range(at: g)))
                }
            }
        }
        let d = closing ? -1 : 1
        func bump(_ v: inout Int) { v = max(0, v + d) }
        func newline() {
            if buf.length > 0 && !buf.string.hasSuffix("\u{2028}") { buf.append(styled("\u{2028}", font: font)) }
        }
        switch name {
        case "br": newline()
        case "img":
            if !closing, let src = attrs["src"] {
                let w = attrs["width"].flatMap { $0.hasSuffix("%") ? nil : Double($0.replacingOccurrences(of: "px", with: "")) }
                buf.append(image(src, alt: attrs["alt"] ?? "", width: w.map { CGFloat($0) }, font: font, link: nil))
            }
        case "b", "strong": bump(&h.bold)
        case "i", "em": bump(&h.italic)
        case "code", "kbd", "tt", "samp": bump(&h.code)
        case "s", "del", "strike": bump(&h.strike)
        case "sup": bump(&h.sup)
        case "sub": bump(&h.sub)
        case "a":
            if closing {
                h.link = nil
            } else {
                if let href = attrs["href"] {
                    h.link = URL(string: href) ?? href.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
                }
                if let id = attrs["id"] ?? attrs["name"] { anchors[id] = out.length + buf.length }
            }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            newline()
            h.heading = closing ? 0 : Int(name.dropFirst())!
        case "p", "div", "li", "tr", "summary", "details", "center", "blockquote", "ul", "ol", "table", "pre", "hr", "dt", "dd":
            newline()
        case "td", "th":
            if closing { buf.append(styled("   ", font: font)) }
        default: break
        }
        if !closing && (attrs["align"]?.lowercased() == "center" || name == "center") {
            h.centerStack.append(name)
            h.centeredBlock = true
        } else if closing, h.centerStack.last == name {
            h.centerStack.removeLast()
        }
    }

    private func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
                     "copy": "©", "reg": "®", "trade": "™", "mdash": "—", "ndash": "–", "hellip": "…",
                     "laquo": "«", "raquo": "»", "middot": "·", "bull": "•", "times": "×", "rarr": "→", "larr": "←"]
        let re = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z]+);")
        let ns = NSMutableString(string: s)
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let body = ns.substring(with: m.range(at: 1))
            var rep: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                rep = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if body.hasPrefix("#") {
                rep = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                rep = named[body]
            }
            if let rep { ns.replaceCharacters(in: m.range, with: rep) }
        }
        return ns as String
    }

    // MARK: blocks

    private func quoteBlock(_ id: Int, margin: CGFloat) -> NSTextBlock {
        if let b = quoteBlocks[id] { return b }
        let b = NSTextBlock()
        b.setContentWidth(100, type: .percentageValueType)
        b.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        b.setBorderColor(Palette.rule, for: .minX)
        b.setWidth(size, type: .absoluteValueType, for: .padding, edge: .minX)
        b.setWidth(margin, type: .absoluteValueType, for: .margin, edge: .minX)
        quoteBlocks[id] = b
        return b
    }

    private func slug(_ s: String) -> String {
        var r = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { r.append(ch) }
            else if ch == " " { r.append("-") }
        }
        let n = slugCounts[r, default: 0]
        slugCounts[r] = n + 1
        return n == 0 ? r : "\(r)-\(n)"
    }

    private func trim(_ m: NSMutableAttributedString) {
        let ws = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{2028}"))
        func isWS(_ c: unichar) -> Bool { Unicode.Scalar(c).map { ws.contains($0) } ?? false }
        let ns = m.string as NSString
        var end = ns.length
        while end > 0 && isWS(ns.character(at: end - 1)) { end -= 1 }
        m.deleteCharacters(in: NSRange(location: end, length: ns.length - end))
        var start = 0
        while start < end && isWS(ns.character(at: start)) { start += 1 }
        m.deleteCharacters(in: NSRange(location: 0, length: start))
    }

    private func flush(_ intent: PresentationIntent?, _ content: NSMutableAttributedString) {
        let comps = intent?.components ?? []
        let kind = comps.first?.kind

        var tableComp: (id: Int, cols: [PresentationIntent.TableColumn])?
        var rowID: Int?, column: Int?, header = false
        for c in comps {
            switch c.kind {
            case .table(let cols): tableComp = (c.identity, cols)
            case .tableRow: rowID = c.identity
            case .tableHeaderRow: rowID = c.identity; header = true
            case .tableCell(let col): column = col
            default: break
            }
        }
        if let t = table, t.id != tableComp?.id { finishTable() }

        // Nesting: quotes (outermost first) and the list depth inside the innermost quote.
        var quotes: [NSTextBlock] = []
        var innerLists = 0, totalLists = 0
        for c in comps.reversed() {
            switch c.kind {
            case .orderedList, .unorderedList: innerLists += 1; totalLists += 1
            case .blockQuote: quotes.append(quoteBlock(c.identity, margin: CGFloat(innerLists) * step)); innerLists = 0
            default: break
            }
        }
        var item: (id: Int, ordinal: Int, ordered: Bool)?
        for (i, c) in comps.enumerated() {
            if case .listItem(let ord) = c.kind {
                var ordered = false
                if i + 1 < comps.count, case .orderedList = comps[i + 1].kind { ordered = true }
                item = (c.identity, ord, ordered)
                break
            }
        }
        let indent = CGFloat(innerLists) * step
        var isCode = false
        if case .codeBlock? = kind { isCode = true }
        let centered = h.centeredBlock || !h.centerStack.isEmpty
        h.centeredBlock = false

        if let tc = tableComp, let col = column, let rid = rowID {
            if table == nil {
                let t = NSTextTable()
                t.numberOfColumns = max(tc.cols.count, 1)
                t.layoutAlgorithm = .automaticLayoutAlgorithm
                t.collapsesBorders = true
                t.hidesEmptyCells = false
                t.setWidth(size * 0.9, type: .absoluteValueType, for: .margin, edge: .maxY)
                if indent > 0 { t.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX) }
                let aligns: [NSTextAlignment] = tc.cols.map {
                    switch $0.alignment {
                    case .center: return .center
                    case .right: return .right
                    default: return .natural
                    }
                }
                table = TableState(id: tc.id, table: t, aligns: aligns, outer: quotes)
            }
            if table!.rowID != rid {
                fillRow()
                table!.row += 1
                table!.rowID = rid
                table!.nextCol = 0
                table!.header = header
            }
            guard col < table!.table.numberOfColumns else { return }
            while table!.nextCol < col { emitCell(NSMutableAttributedString(), table!.nextCol) }
            emitCell(content, col)
            return
        }

        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.3
        ps.paragraphSpacing = size * 0.8
        ps.headIndent = indent
        ps.firstLineHeadIndent = indent
        var blocks = quotes
        var body = content
        var align = centered

        switch kind {
        case .header(let level)?:
            anchors[slug(content.string)] = out.length
            ps.lineHeightMultiple = 1.1
            ps.paragraphSpacingBefore = out.length == 0 ? 0 : size * (level <= 2 ? 1.3 : 0.9)
            ps.paragraphSpacing = size * (level <= 2 ? 0.7 : 0.45)
            if level <= 2 {
                let b = NSTextBlock()
        b.setContentWidth(100, type: .percentageValueType)
                b.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
                b.setBorderColor(Palette.rule, for: .maxY)
                b.setWidth(size * 0.3, type: .absoluteValueType, for: .padding, edge: .maxY)
                if indent > 0 { b.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX) }
                blocks.append(b)
                ps.headIndent = 0
                ps.firstLineHeadIndent = 0
            }
            if level == 6 {
                body.addAttribute(.foregroundColor, value: Palette.muted, range: NSRange(location: 0, length: body.length))
            }
        case .codeBlock?:
            if body.string.hasSuffix("\n") { body.deleteCharacters(in: NSRange(location: body.length - 1, length: 1)) }
            let b = NSTextBlock()
        b.setContentWidth(100, type: .percentageValueType)
            b.backgroundColor = Palette.codeBg
            b.setWidth(size * 0.8, type: .absoluteValueType, for: .padding, edge: .minY)
            b.setWidth(size * 0.8, type: .absoluteValueType, for: .padding, edge: .maxY)
            b.setWidth(size, type: .absoluteValueType, for: .padding, edge: .minX)
            b.setWidth(size, type: .absoluteValueType, for: .padding, edge: .maxX)
            b.setWidth(size * 0.8, type: .absoluteValueType, for: .margin, edge: .maxY)
            if indent > 0 { b.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX) }
            blocks.append(b)
            ps.lineHeightMultiple = 1.15
            ps.paragraphSpacing = 0
            ps.headIndent = 0
            ps.firstLineHeadIndent = 0
            align = false
            if body.length == 0 { body = NSMutableAttributedString(string: " ", attributes: [.font: mono(size * 0.86)]) }
        case .thematicBreak?:
            body = NSMutableAttributedString(string: "\u{00A0}", attributes: [.font: NSFont.systemFont(ofSize: 2)])
            let b = NSTextBlock()
        b.setContentWidth(100, type: .percentageValueType)
            b.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
            b.setBorderColor(Palette.rule, for: .maxY)
            blocks.append(b)
            ps.lineHeightMultiple = 1
            ps.paragraphSpacingBefore = size * 0.6
            ps.paragraphSpacing = size * 1.4
        case nil:
            trim(body)
            if body.length == 0 { return }
        default:
            break
        }

        var prefix: NSAttributedString?
        if let item, !seenItems.contains(item.id) {
            seenItems.insert(item.id)
            var marker = item.ordered ? "\(item.ordinal)." : ["•", "◦", "▪"][(max(totalLists, 1) - 1) % 3]
            let s = body.string
            if s.hasPrefix("[ ] ") || s.hasPrefix("[x] ") || s.hasPrefix("[X] ") {
                marker = s.hasPrefix("[ ]") ? "☐" : "☑"
                body.deleteCharacters(in: NSRange(location: 0, length: 4))
            }
            if innerLists > 0, !isCode {
                ps.firstLineHeadIndent = indent - step
                ps.tabStops = [NSTextTab(textAlignment: .right, location: indent - step * 0.35),
                               NSTextTab(textAlignment: .left, location: indent)]
                let color = item.ordered ? Palette.text : Palette.muted
                prefix = NSAttributedString(string: "\t\(marker)\t", attributes: [.font: self.body, .foregroundColor: color])
            }
        }

        let inList = item != nil
        if inList, !isCode {
            ps.paragraphSpacing = size * 0.3
        }
        if !inList, prevInList, ps.paragraphSpacingBefore == 0 {
            ps.paragraphSpacingBefore = size * 0.5
        }
        prevInList = inList
        if align { ps.alignment = .center }
        ps.textBlocks = blocks

        let p = NSMutableAttributedString()
        if let prefix { p.append(prefix) }
        p.append(body)
        let endFont = body.length > 0 ? (body.attribute(.font, at: body.length - 1, effectiveRange: nil) as? NSFont ?? self.body) : self.body
        p.append(NSAttributedString(string: "\n", attributes: [.font: endFont]))
        p.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: p.length))
        out.append(p)
    }

    private func emitCell(_ content: NSMutableAttributedString, _ col: Int) {
        guard let t = table else { return }
        let b = NSTextTableBlock(table: t.table, startingRow: t.row, rowSpan: 1, startingColumn: col, columnSpan: 1)
        b.setWidth(1, type: .absoluteValueType, for: .border)
        b.setBorderColor(Palette.rule)
        b.setWidth(size * 0.4, type: .absoluteValueType, for: .padding, edge: .minY)
        b.setWidth(size * 0.4, type: .absoluteValueType, for: .padding, edge: .maxY)
        b.setWidth(size * 0.8, type: .absoluteValueType, for: .padding, edge: .minX)
        b.setWidth(size * 0.8, type: .absoluteValueType, for: .padding, edge: .maxX)
        let p = NSMutableAttributedString(attributedString: content)
        if t.header {
            b.backgroundColor = Palette.codeBg
            p.enumerateAttribute(.font, in: NSRange(location: 0, length: p.length)) { v, r, _ in
                if let f = v as? NSFont { p.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask), range: r) }
            }
        }
        let ps = NSMutableParagraphStyle()
        ps.alignment = col < t.aligns.count ? t.aligns[col] : .natural
        ps.lineHeightMultiple = 1.15
        ps.textBlocks = t.outer + [b]
        p.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        p.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: p.length))
        out.append(p)
        table!.nextCol = col + 1
    }

    private func fillRow() {
        guard let t = table, t.row >= 0 else { return }
        while table!.nextCol < t.table.numberOfColumns { emitCell(NSMutableAttributedString(), table!.nextCol) }
    }

    private func finishTable() {
        guard table != nil else { return }
        fillRow()
        table = nil
        prevInList = false
    }

    // MARK: preprocessing (front matter, footnotes)

    private func preprocess(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n")
        if t.hasPrefix("---\n") {
            let start = t.index(t.startIndex, offsetBy: 4)
            if let end = t.range(of: "\n---\n", range: start..<t.endIndex) ?? t.range(of: "\n...\n", range: start..<t.endIndex) {
                t = "```yaml\n" + t[start..<end.lowerBound] + "\n```\n" + t[end.upperBound...]
            }
        }
        guard t.contains("[^") else { return t }
        let defRe = try! NSRegularExpression(pattern: "^\\[\\^([^\\]\\s]+)\\]:[ \\t]*(.*)$", options: .anchorsMatchLines)
        let ns = t as NSString
        var defs: [(id: String, text: String)] = []
        for m in defRe.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            defs.append((ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2))))
        }
        guard !defs.isEmpty else { return t }
        t = defRe.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        var number: [String: Int] = [:]
        for (i, d) in defs.enumerated() where number[d.id] == nil { number[d.id] = i + 1 }
        let refRe = try! NSRegularExpression(pattern: "\\[\\^([^\\]\\s]+)\\]")
        let m = NSMutableString(string: t)
        for r in refRe.matches(in: t, range: NSRange(location: 0, length: m.length)).reversed() {
            let id = m.substring(with: r.range(at: 1))
            if let n = number[id] {
                m.replaceCharacters(in: r.range, with: "<sup><a href=\"#fn-\(id)\">\(n)</a></sup>")
            }
        }
        let notes = defs.map { "<a id=\"fn-\($0.id)\"></a><sup>\(number[$0.id]!)</sup> \($0.text)" }
        return (m as String) + "\n\n---\n\n" + notes.joined(separator: "\n\n") + "\n"
    }
}
