import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var viewers: [Viewer] = []

    func applicationWillFinishLaunching(_ n: Notification) {
        if let a = ProcessInfo.processInfo.environment["MYMD_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua)
        } else if let a = UserDefaults.standard.string(forKey: "appearance") {
            NSApp.appearance = NSAppearance(named: NSAppearance.Name(a))
        }
        buildMenu()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        for a in args { open(URL(fileURLWithPath: a)) }
        NSApp.activate(ignoringOtherApps: true)
        if viewers.isEmpty { openDocument(nil) }

        // Snapshot mode (see `make screenshots`): MYMD_SNAPSHOT=out.pdf, optional
        // MYMD_SNAPSHOT_SIZE=WxH and MYMD_SNAPSHOT_FULL=1 for the whole document.
        let env = ProcessInfo.processInfo.environment
        if let snap = env["MYMD_SNAPSHOT"], let v = viewers.first {
            v.window.setFrameAutosaveName("")   // don't persist the snapshot's window size
            if let dims = env["MYMD_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), dims.count == 2 {
                v.window.setContentSize(NSSize(width: dims[0], height: dims[1]))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                v.snapshot(to: snap, full: env["MYMD_SNAPSHOT_FULL"] != nil)
                NSApp.terminate(nil)
            }
        }
    }

    func application(_ sender: NSApplication, openFiles names: [String]) {
        for n in names { open(URL(fileURLWithPath: n)) }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func open(_ url: URL) {
        let u = url.standardizedFileURL
        if let v = viewers.first(where: { $0.url.standardizedFileURL == u }) {
            v.window.makeKeyAndOrderFront(nil)
            return
        }
        guard FileManager.default.isReadableFile(atPath: u.path) else {
            FileHandle.standardError.write("mymd: cannot open \(u.path)\n".data(using: .utf8)!)
            return
        }
        let v = Viewer(url: u)
        v.onClose = { [weak self] v in self?.viewers.removeAll { $0 === v } }
        if let last = viewers.last {
            let tl = NSPoint(x: last.window.frame.minX, y: last.window.frame.maxY)
            v.window.setFrameTopLeftPoint(v.window.cascadeTopLeft(from: tl))
        }
        viewers.append(v)
        v.window.makeKeyAndOrderFront(nil)
    }

    private var active: Viewer? { viewers.first { $0.window.isKeyWindow } ?? viewers.last }

    @objc func openDocument(_ sender: Any?) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        if p.runModal() == .OK {
            p.urls.forEach(open)
        }
        if viewers.isEmpty { NSApp.terminate(nil) }
    }

    // MARK: open recent (backed by NSDocumentController, which also feeds the Dock menu)

    private let recentMenu = NSMenu(title: "Open Recent")

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        let names = urls.map { FileManager.default.displayName(atPath: $0.path) }
        for (url, name) in zip(urls, names) {
            // Disambiguate same-named files (README.md) with their folder, like Finder.
            let dup = names.filter { $0 == name }.count > 1
            let title = dup ? "\(name) — \(url.deletingLastPathComponent().lastPathComponent)" : name
            let item = menu.addItem(withTitle: title, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = menu.addItem(withTitle: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !urls.isEmpty
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if FileManager.default.isReadableFile(atPath: url.path) { open(url) } else { NSSound.beep() }
    }

    @objc func clearRecent(_ sender: Any?) { NSDocumentController.shared.clearRecentDocuments(sender) }

    @objc func closeWindow(_ sender: Any?) { NSApp.keyWindow?.close() }
    @objc func reload(_ sender: Any?) { active?.reload() }
    @objc func find(_ sender: Any?) { active?.beginSearch() }
    @objc func zoomIn(_ sender: Any?) { active?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { active?.zoomOut() }
    @objc func zoomReset(_ sender: Any?) { active?.zoomReset() }
    @objc func toggleDark(_ sender: Any?) { active?.toggleAppearance() }
    @objc func toggleBar(_ sender: Any?) { active?.toggleBar() }

    private func buildMenu() {
        let main = NSMenu()
        @discardableResult
        func menu(_ title: String, _ items: [(String, Selector?, String, NSEvent.ModifierFlags)]) -> NSMenu {
            let item = NSMenuItem()
            let m = NSMenu(title: title)
            for (t, sel, key, mods) in items {
                if t == "-" { m.addItem(.separator()); continue }
                let i = m.addItem(withTitle: t, action: sel, keyEquivalent: key)
                i.keyEquivalentModifierMask = mods
            }
            item.submenu = m
            main.addItem(item)
            return m
        }
        menu("mymd", [("Hide mymd", #selector(NSApplication.hide(_:)), "h", .command),
                      ("-", nil, "", []),
                      ("Quit mymd", #selector(NSApplication.terminate(_:)), "q", .command)])
        let file = menu("File", [("Open…", #selector(openDocument(_:)), "o", .command),
                      ("Reload", #selector(reload(_:)), "r", .command),
                      ("Close", #selector(closeWindow(_:)), "w", .command)])
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentMenu.autoenablesItems = false
        recent.submenu = recentMenu
        file.insertItem(recent, at: 1)
        menu("Edit", [("Copy", #selector(NSText.copy(_:)), "c", .command),
                      ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
                      ("Find", #selector(find(_:)), "f", .command)])
        menu("View", [("Zoom In", #selector(zoomIn(_:)), "=", .command),
                      ("Zoom Out", #selector(zoomOut(_:)), "-", .command),
                      ("Actual Size", #selector(zoomReset(_:)), "0", .command),
                      ("-", nil, "", []),
                      ("Toggle Dark Mode", #selector(toggleDark(_:)), "d", [.command, .shift]),
                      ("Toggle Status Bar", #selector(toggleBar(_:)), "b", [.command, .shift])])
        menu("Window", [("Minimize", #selector(NSWindow.miniaturize(_:)), "m", .command)])
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
