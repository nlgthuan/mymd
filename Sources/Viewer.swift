import AppKit

final class MDTextView: NSTextView {
    weak var viewer: Viewer?

    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command) { return super.keyDown(with: e) }
        viewer?.handleKey(e)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        viewer?.appearanceChanged()
    }
}

/// Lays out the scroll view above a one-line bar (status / input), zathura style.
final class Container: NSView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class Bar: NSView {
    override func draw(_ r: NSRect) {
        Palette.bar.setFill()
        bounds.fill()
    }
}

final class Viewer: NSObject, NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    let window: NSWindow
    private let container = Container()
    private let scroll = NSScrollView()
    private let text: MDTextView
    private let bar = Bar()
    private let left = NSTextField(labelWithString: "")
    private let right = NSTextField(labelWithString: "")
    private let input = NSTextField()

    private(set) var url: URL
    var onClose: ((Viewer) -> Void)?

    private var zoom: CGFloat
    private var anchors: [String: Int] = [:]
    private var images: [ImageRef] = []
    private var lastSource: String?
    private var history: [(URL, CGFloat)] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadPending = false

    private var pendingG = false
    private var inputActive = false
    private var searchBackwards = false
    private var searchOrigin = 0
    private var lastSearch: (String, Bool)?
    private var hints: [(key: String, label: NSTextField, url: URL)] = []
    private var hintTyped = ""
    private var messageToken = 0

    private static var showBar: Bool {
        get { UserDefaults.standard.object(forKey: "statusbar") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "statusbar") }
    }

    init(url: URL) {
        self.url = url
        zoom = UserDefaults.standard.object(forKey: "zoom") as? CGFloat ?? 1

        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        text = MDTextView(frame: .zero, textContainer: tc)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 1000),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = true
        }
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.backgroundColor = Palette.bg
        window.delegate = self
        window.minSize = NSSize(width: 320, height: 240)

        text.viewer = self
        text.delegate = self
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = true
        text.backgroundColor = Palette.bg
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.linkTextAttributes = [.foregroundColor: Palette.link, .cursor: NSCursor.pointingHand]
        text.textContainerInset = NSSize(width: 40, height: 44)

        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)

        let barFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        for l in [left, right] {
            l.font = barFont
            l.textColor = Palette.muted
            l.lineBreakMode = .byTruncatingMiddle
            bar.addSubview(l)
        }
        right.alignment = .right
        input.font = barFont
        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.textColor = Palette.text
        input.delegate = self
        input.isHidden = true
        input.cell?.usesSingleLineMode = true
        bar.addSubview(input)

        container.addSubview(scroll)
        container.addSubview(bar)
        container.onLayout = { [weak self] in self?.layoutViews() }
        window.contentView = container

        load(url)
        window.setFrameAutosaveName("mymd")
    }

    // MARK: layout

    private func layoutViews() {
        let b = container.bounds
        let barH: CGFloat = (Self.showBar || inputActive) ? 20 : 0
        bar.isHidden = barH == 0
        bar.frame = NSRect(x: 0, y: 0, width: b.width, height: barH)
        scroll.frame = NSRect(x: 0, y: barH, width: b.width, height: b.height - barH)
        // Keep the text view exactly as wide as the viewport and at least as tall;
        // a stale taller frame would leave phantom scroll room after a resize.
        let viewport = scroll.contentSize
        if text.frame.width != viewport.width || text.minSize.height != viewport.height {
            text.minSize = NSSize(width: 0, height: viewport.height)
            text.setFrameSize(NSSize(width: viewport.width, height: text.frame.height))
            text.sizeToFit()
        }
        let pad: CGFloat = 10
        let rw: CGFloat = 60
        right.frame = NSRect(x: b.width - rw - pad, y: 3, width: rw, height: 14)
        if inputActive {
            left.frame = NSRect(x: pad, y: 3, width: 10, height: 14)
            input.frame = NSRect(x: pad + 10, y: 2, width: b.width - 2 * pad - 10 - rw, height: 16)
        } else {
            left.frame = NSRect(x: pad, y: 3, width: b.width - 3 * pad - rw, height: 14)
        }
        updateInsets()
    }

    private var contentWidth: CGFloat { scroll.contentSize.width - 2 * text.textContainerInset.width }

    private func updateInsets() {
        let w = scroll.contentSize.width
        let side = floor(max(24, (w - 740 * zoom) / 2))
        if text.textContainerInset.width != side {
            text.textContainerInset = NSSize(width: side, height: 44)
            refitImages()
        }
    }

    // MARK: loading

    func load(_ u: URL, keepY: CGFloat? = nil) {
        guard let data = try? Data(contentsOf: u) else {
            flash("cannot read \(u.path)", error: true)
            return
        }
        let src = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if u != url { watcher?.cancel(); watcher = nil }
        url = u
        lastSource = src
        NSDocumentController.shared.noteNewRecentDocumentURL(u)
        window.title = u.lastPathComponent
        window.representedURL = u
        render(src, keepY: keepY)
        if watcher == nil { watch() }
    }

    private func render(_ src: String, keepY: CGFloat?) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let dark = text.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let r = Renderer(base: url.deletingLastPathComponent(), size: 15 * zoom, dark: dark)
        let s = r.render(src)
        let t1 = CFAbsoluteTimeGetCurrent()
        text.textStorage?.setAttributedString(s)
        if ProcessInfo.processInfo.environment["MYMD_TIMING"] != nil {
            text.layoutManager?.ensureLayout(for: text.textContainer!)
            print(String(format: "parse+build %.0fms, full layout %.0fms", (t1 - t0) * 1000, (CFAbsoluteTimeGetCurrent() - t1) * 1000))
        }
        anchors = r.anchors
        images = r.images
        updateInsets()
        refitImages()
        loadImages()
        if let y = keepY, y > 0 {
            text.layoutManager?.ensureLayout(for: text.textContainer!)
            setY(y)
        } else {
            setY(0)
        }
        updateStatus()
    }

    /// Math is rasterised in the current text colour, so re-render on theme change.
    func appearanceChanged() {
        guard let src = lastSource, src.contains("$") || src.contains("\\(") || src.contains("```math") else { return }
        render(src, keepY: scroll.contentView.bounds.minY)
    }

    func reload() {
        guard let data = try? Data(contentsOf: url) else { return }
        let src = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if src == lastSource { return }
        lastSource = src
        render(src, keepY: scroll.contentView.bounds.minY)
    }

    private func watch() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            if !src.data.isDisjoint(with: [.delete, .rename]) {
                // Atomic saves replace the file: re-attach to the new inode.
                src.cancel()
                self.watcher = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.watch(); self.reload() }
            } else if !self.reloadPending {
                self.reloadPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.reloadPending = false; self.reload() }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    // MARK: images

    private func loadImages() {
        for ref in images where ref.image == nil {
            let u = ref.url
            let done: (NSImage?) -> Void = { [weak self] img in
                DispatchQueue.main.async {
                    if let img { ImageCache.images[u] = img }
                    self?.apply(ref, img)
                }
            }
            if u.isFileURL {
                DispatchQueue.global(qos: .userInitiated).async { done(NSImage(contentsOf: u)) }
            } else {
                URLSession.shared.dataTask(with: u) { data, _, _ in done(data.flatMap(NSImage.init(data:))) }.resume()
            }
        }
    }

    private func range(of att: NSTextAttachment) -> NSRange? {
        guard let s = text.textStorage else { return nil }
        var found: NSRange?
        s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, r, stop in
            if (v as AnyObject?) === att { found = r; stop.pointee = true }
        }
        return found
    }

    private func apply(_ ref: ImageRef, _ img: NSImage?) {
        guard images.contains(where: { $0 === ref }), let s = text.textStorage, let r = range(of: ref.attachment) else { return }
        s.beginEditing()
        if let img {
            let att = NSTextAttachment()
            att.image = img
            att.bounds = Renderer.fit(img, width: ref.width, max: contentWidth)
            ref.attachment = att
            ref.image = img
            s.addAttribute(.attachment, value: att, range: r)
        } else {
            let alt = ref.alt.isEmpty ? "[image]" : ref.alt
            var a = s.attributes(at: r.location, effectiveRange: nil)
            a[.attachment] = nil
            a[.foregroundColor] = Palette.muted
            s.replaceCharacters(in: r, with: NSAttributedString(string: alt, attributes: a))
            images.removeAll { $0 === ref }
        }
        s.endEditing()
    }

    private func refitImages() {
        guard let s = text.textStorage, s.length > 0 else { return }
        var changed = false
        for ref in images {
            guard let img = ref.image else { continue }
            let b = Renderer.fit(img, width: ref.width, max: contentWidth)
            if ref.attachment.bounds != b { ref.attachment.bounds = b; changed = true }
        }
        if changed {
            s.beginEditing()
            s.edited(.editedAttributes, range: NSRange(location: 0, length: s.length), changeInLength: 0)
            s.endEditing()
        }
    }

    // MARK: scrolling

    private var maxY: CGFloat { max(0, text.frame.height - scroll.contentView.bounds.height) }

    private func setY(_ y: CGFloat) {
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        scroll.reflectScrolledClipView(clip)
    }

    private func scrollBy(_ dy: CGFloat) { setY(scroll.contentView.bounds.minY + dy) }

    @objc private func scrolled() { updateStatus() }

    private func charRect(_ i: Int) -> NSRect? {
        guard let lm = text.layoutManager, let tc = text.textContainer, let s = text.textStorage, s.length > 0 else { return nil }
        let g = lm.glyphIndexForCharacter(at: min(i, s.length - 1))
        lm.ensureLayout(forGlyphRange: NSRange(location: 0, length: g + 1))
        _ = tc
        let r = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let o = text.textContainerOrigin
        return r.offsetBy(dx: o.x, dy: o.y)
    }

    private func scrollTo(char i: Int) {
        guard let r = charRect(i) else { return }
        setY(r.minY - 16)
    }

    private func center(_ range: NSRange) {
        guard let r = charRect(range.location) else { return }
        let vis = scroll.contentView.bounds
        if !vis.insetBy(dx: 0, dy: 40).contains(r) { setY(r.midY - vis.height / 2) }
    }

    private func pushHistory() {
        history.append((url, scroll.contentView.bounds.minY))
        if history.count > 100 { history.removeFirst() }
    }

    private func back() {
        guard let (u, y) = history.popLast() else { return flash("no history") }
        if u == url { setY(y) } else { load(u, keepY: y) }
    }

    // MARK: links

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let u = link as? URL { follow(u) } else if let s = link as? String, let u = URL(string: s) { follow(u) }
        return true
    }

    private func follow(_ u: URL) {
        let s = u.absoluteString
        guard u.scheme == nil || u.isFileURL else { NSWorkspace.shared.open(u); return }
        if s.hasPrefix("#") { return jump(String(s.dropFirst())) }
        let target = u.isFileURL ? u : URL(string: s, relativeTo: url.deletingLastPathComponent())?.absoluteURL
        guard let target else { return flash("bad link: \(s)", error: true) }
        let file = URL(fileURLWithPath: target.path)
        let frag = target.fragment
        if ["md", "markdown", "mdown", "mkd", "mkdn", "txt"].contains(file.pathExtension.lowercased()) {
            if file.standardizedFileURL != url.standardizedFileURL {
                pushHistory()
                load(file)
            }
            if let frag { jump(frag, push: false) }
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    private func jump(_ anchor: String, push: Bool = true) {
        let a = anchor.removingPercentEncoding ?? anchor
        guard let i = anchors[a] ?? anchors[a.lowercased()] else { return flash("no anchor #\(a)", error: true) }
        if push { pushHistory() }
        scrollTo(char: i)
    }

    private func showHints() {
        guard let lm = text.layoutManager, let tc = text.textContainer, let s = text.textStorage else { return }
        let vis = scroll.contentView.bounds
        let o = text.textContainerOrigin
        let gr = lm.glyphRange(forBoundingRect: vis.offsetBy(dx: -o.x, dy: -o.y), in: tc)
        let cr = lm.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
        var found: [(NSRect, URL)] = []
        s.enumerateAttribute(.link, in: cr) { v, r, _ in
            let u = (v as? URL) ?? (v as? String).flatMap(URL.init(string:))
            guard let u else { return }
            let g = lm.glyphRange(forCharacterRange: NSRange(location: r.location, length: 1), actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: g, in: tc).offsetBy(dx: o.x, dy: o.y)
            if vis.intersects(rect) { found.append((rect, u)) }
        }
        guard !found.isEmpty else { return flash("no links") }
        let digits = String(found.count).count
        for (i, (rect, u)) in found.enumerated() {
            let key = String(repeating: "0", count: digits - String(i + 1).count) + String(i + 1)
            let l = NSTextField(labelWithString: key)
            l.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
            l.textColor = .black
            l.backgroundColor = Palette.hint
            l.drawsBackground = true
            l.sizeToFit()
            l.frame.origin = NSPoint(x: max(0, rect.minX - 4), y: max(0, rect.minY - 6))
            text.addSubview(l)
            hints.append((key, l, u))
        }
        hintTyped = ""
    }

    private func clearHints() {
        hints.forEach { $0.label.removeFromSuperview() }
        hints = []
        hintTyped = ""
    }

    private func hintKey(_ e: NSEvent) {
        let ch = e.charactersIgnoringModifiers ?? ""
        if e.keyCode == 53 { return clearHints() }
        if e.keyCode == 51 { hintTyped = String(hintTyped.dropLast()); return }
        guard let c = ch.first, c.isNumber else { return clearHints() }
        hintTyped.append(c)
        let matches = hints.filter { $0.key.hasPrefix(hintTyped) }
        if matches.count == 1 || matches.first?.key == hintTyped, let m = matches.first, m.key == hintTyped {
            let u = m.url
            clearHints()
            follow(u)
        } else if matches.isEmpty {
            clearHints()
        }
    }

    // MARK: search

    private func beginInput(backwards: Bool) {
        searchBackwards = backwards
        inputActive = true
        left.stringValue = backwards ? "?" : "/"
        left.textColor = Palette.text
        input.stringValue = ""
        input.isHidden = false
        searchOrigin = visibleStart()
        layoutViews()
        window.makeFirstResponder(input)
    }

    private func endInput() {
        inputActive = false
        input.isHidden = true
        layoutViews()
        updateStatus()
        window.makeFirstResponder(text)
    }

    private func visibleStart() -> Int {
        guard let lm = text.layoutManager, let tc = text.textContainer else { return 0 }
        let o = text.textContainerOrigin
        let p = NSPoint(x: 0, y: scroll.contentView.bounds.minY - o.y)
        return lm.characterIndexForGlyph(at: lm.glyphIndex(for: p, in: tc))
    }

    @discardableResult
    private func find(_ q: String, from: Int, backwards: Bool) -> Bool {
        guard !q.isEmpty else { return false }
        let s = text.string as NSString
        var opts: NSString.CompareOptions = [.diacriticInsensitive]
        if q.lowercased() == q { opts.insert(.caseInsensitive) }
        if backwards { opts.insert(.backwards) }
        let from = min(max(0, from), s.length)
        var r = backwards ? s.range(of: q, options: opts, range: NSRange(location: 0, length: from))
                          : s.range(of: q, options: opts, range: NSRange(location: from, length: s.length - from))
        if r.location == NSNotFound { r = s.range(of: q, options: opts) }
        guard r.location != NSNotFound else {
            flash("pattern not found: \(q)", error: true)
            return false
        }
        text.setSelectedRange(r)
        center(r)
        text.showFindIndicator(for: r)
        return true
    }

    private func searchNext(reverse: Bool) {
        guard let (q, back) = lastSearch else { return }
        let b = back != reverse
        let sel = text.selectedRange()
        find(q, from: b ? sel.location : sel.location + max(sel.length, 1), backwards: b)
    }

    func controlTextDidChange(_ n: Notification) {
        let q = input.stringValue
        if q.isEmpty { return }
        let s = text.string as NSString
        var opts: NSString.CompareOptions = [.diacriticInsensitive]
        if q.lowercased() == q { opts.insert(.caseInsensitive) }
        let r = s.range(of: q, options: opts, range: NSRange(location: searchOrigin, length: s.length - searchOrigin))
        if r.location != NSNotFound { text.setSelectedRange(r); center(r) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let q = input.stringValue
            endInput()
            if !q.isEmpty {
                lastSearch = (q, searchBackwards)
                find(q, from: searchOrigin, backwards: searchBackwards)
            }
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            endInput()
            return true
        }
        return false
    }

    // MARK: status

    private func updateStatus() {
        guard !inputActive else { return }
        left.stringValue = (url.path as NSString).abbreviatingWithTildeInPath
        left.textColor = Palette.muted
        let y = scroll.contentView.bounds.minY
        let m = maxY
        right.stringValue = m <= 1 ? "All" : y <= 0 ? "Top" : y >= m - 1 ? "Bot" : "\(Int((y / m * 100).rounded()))%"
    }

    func flash(_ msg: String, error: Bool = false) {
        guard !inputActive else { return }
        if error && !Self.showBar { NSSound.beep() }
        left.stringValue = msg
        left.textColor = error ? Palette.error : Palette.text
        messageToken += 1
        let t = messageToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.messageToken == t { self?.updateStatus() }
        }
    }

    // MARK: commands

    func setZoom(_ z: CGFloat) {
        let nz = min(max(z, 0.5), 3)
        guard nz != zoom else { return }
        let frac = maxY > 0 ? scroll.contentView.bounds.minY / maxY : 0
        zoom = nz
        UserDefaults.standard.set(Double(nz), forKey: "zoom")
        text.textContainerInset = .zero // force inset recompute
        render(lastSource ?? "", keepY: nil)
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        setY(frac * maxY)
        flash("zoom \(Int((zoom * 100).rounded()))%")
    }

    func zoomIn() { setZoom(zoom * 1.1) }
    func zoomOut() { setZoom(zoom / 1.1) }
    func zoomReset() { setZoom(1) }
    func beginSearch() { beginInput(backwards: false) }

    func toggleBar() {
        Self.showBar.toggle()
        layoutViews()
    }

    func handleKey(_ e: NSEvent) {
        if !hints.isEmpty { return hintKey(e) }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ctrl = mods.contains(.control)
        let shift = mods.contains(.shift)
        let ch = e.charactersIgnoringModifiers ?? ""
        let page = scroll.contentView.bounds.height
        let line: CGFloat = 50 * zoom

        if pendingG {
            pendingG = false
            if ch == "g" && !ctrl { return setY(0) }
        }
        switch e.keyCode {
        case 125: return scrollBy(line)              // down
        case 126: return scrollBy(-line)             // up
        case 121: return scrollBy(page - line)       // page down
        case 116: return scrollBy(-(page - line))    // page up
        case 115: return setY(0)                     // home
        case 119: return setY(maxY)                  // end
        case 51: return back()                       // backspace
        case 53:                                     // esc
            text.setSelectedRange(NSRange(location: text.selectedRange().location, length: 0))
            return updateStatus()
        case 49: return scrollBy(shift ? -(page - line) : page - line) // space
        default: break
        }
        if ctrl {
            switch ch {
            case "d": scrollBy(page / 2)
            case "u": scrollBy(-page / 2)
            case "f": scrollBy(page - line)
            case "b": scrollBy(-(page - line))
            case "e": scrollBy(line)
            case "y": scrollBy(-line)
            case "o": back()
            case "r": toggleAppearance()
            case "n": toggleBar()
            default: break
            }
            return
        }
        switch ch {
        case "j": scrollBy(line)
        case "k": scrollBy(-line)
        case "d": scrollBy(page / 2)
        case "u": scrollBy(-page / 2)
        case "J": scrollBy(page - line)
        case "K": scrollBy(-(page - line))
        case "g": pendingG = true
        case "G": setY(maxY)
        case "/": beginInput(backwards: false)
        case "?": beginInput(backwards: true)
        case "n": searchNext(reverse: false)
        case "N": searchNext(reverse: true)
        case "f": showHints()
        case "+", "=": zoomIn()
        case "-": zoomOut()
        case "0": zoomReset()
        case "r", "R": lastSource = nil; reload(); flash("reloaded")
        case "i": toggleAppearance()
        case "o": (NSApp.delegate as? AppDelegate)?.openDocument(nil)
        case "q": window.close()
        default: break
        }
    }

    func toggleAppearance() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name: NSAppearance.Name = dark ? .aqua : .darkAqua
        NSApp.appearance = NSAppearance(named: name)
        UserDefaults.standard.set(name.rawValue, forKey: "appearance")
    }

    // MARK: window

    func windowWillClose(_ n: Notification) {
        watcher?.cancel()
        NotificationCenter.default.removeObserver(self)
        onClose?(self)
    }

    func windowDidResize(_ n: Notification) { updateStatus() }

    func snapshot(to path: String) {
        let pdf = text.dataWithPDF(inside: text.bounds)
        try? pdf.write(to: URL(fileURLWithPath: path))
    }

}
