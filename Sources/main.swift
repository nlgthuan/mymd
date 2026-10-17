import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewers: [Viewer] = []

    func applicationWillFinishLaunching(_ n: Notification) {
        if let a = UserDefaults.standard.string(forKey: "appearance") {
            NSApp.appearance = NSAppearance(named: NSAppearance.Name(a))
        }
        buildMenu()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        for a in args { open(URL(fileURLWithPath: a)) }
        NSApp.activate(ignoringOtherApps: true)
        if viewers.isEmpty { openDocument(nil) }

        if let snap = ProcessInfo.processInfo.environment["MYMD_SNAPSHOT"], let v = viewers.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                v.snapshot(to: snap)
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
        func menu(_ title: String, _ items: [(String, Selector?, String, NSEvent.ModifierFlags)]) {
            let item = NSMenuItem()
            let m = NSMenu(title: title)
            for (t, sel, key, mods) in items {
                if t == "-" { m.addItem(.separator()); continue }
                let i = m.addItem(withTitle: t, action: sel, keyEquivalent: key)
                i.keyEquivalentModifierMask = mods
            }
            item.submenu = m
            main.addItem(item)
        }
        menu("mymd", [("Hide mymd", #selector(NSApplication.hide(_:)), "h", .command),
                      ("-", nil, "", []),
                      ("Quit mymd", #selector(NSApplication.terminate(_:)), "q", .command)])
        menu("File", [("Open…", #selector(openDocument(_:)), "o", .command),
                      ("Reload", #selector(reload(_:)), "r", .command),
                      ("Close", #selector(closeWindow(_:)), "w", .command)])
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
