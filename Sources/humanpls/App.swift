import SwiftUI
import AppKit
import HumanplsCore

// MARK: one popup window

/// The first click on an inactive popup must also act (select, press a button), not only focus the window.
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PopupWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let job: Job
    var finished = false
    var onDone: (FinishAction, String, Picks?) -> Void
    var autoText: (() -> String)?
    var autoPicks: (() -> Picks?)?

    init<V: View>(job: Job, title: String, autosave: String, size: NSSize, content: V,
                  onDone: @escaping (FinishAction, String, Picks?) -> Void) {
        self.job = job; self.onDone = onDone
        self.sizeKey = "size." + autosave
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.level = .floating
        // Show on the desktop (Space) you are on now, also over a full-screen terminal.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = FirstMouseHostingView(rootView: content)
        // Remember the size only. The position is always the screen where the mouse is now (you may use several displays).
        var s = size
        if let saved = UserDefaults.standard.string(forKey: sizeKey) {
            let r = NSSizeFromString(saved)
            if r.width >= 480, r.height >= 360 { s = r }
        }
        placeOnMouseScreen(s)
    }

    let sizeKey: String

    func placeOnMouseScreen(_ size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            let w = min(size.width, f.width - 40), h = min(size.height, f.height - 40)
            window.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: false)
        } else { window.center() }
    }

    func windowDidEndLiveResize(_ n: Notification) {
        UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: sizeKey)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func finish(_ a: FinishAction, _ text: String, _ picks: Picks?) {
        guard !finished else { return }
        finished = true
        onDone(a, text, picks)
        window.close()
    }

    func windowWillClose(_ n: Notification) {
        if !finished { finished = true; onDone(.cancel, "", nil) }
    }
}

// MARK: controller

@MainActor
final class Controller {
    let history = HistoryStore()
    var open: [String: PopupWindow] = [:]
    /// Test mode (set by the CLI per request): answer at once with the default picks and open no window.
    static func autoAction(_ env: ClientEnv) -> FinishAction? {
        switch env.autoAnswer {
        case "send": return .send
        case "copy": return .copy
        case "cancel": return .cancel
        default: return nil
        }
    }

    func open(job: Job, picks: Picks? = nil, env: ClientEnv, wait: Bool, reply: @escaping (Response) -> Void) {
        open[job.id]?.finish(.cancel, "", nil)           // same id again: replace the old popup
        history.save(HistoryEntry(job: job, picks: picks))
        reply(Response(type: "accepted", message: job.id))

        let popup: PopupWindow
        let finishNow: (FinishAction, String, Picks?) -> Void = { [weak self] action, text, p in
            self?.finished(job: job, action: action, text: text, picks: p, env: env, wait: wait, reply: reply)
        }
        switch job.mode {
        case .pick:
            let model = PickModel(job: job, picks: picks, waiting: wait)
            popup = PopupWindow(job: job, title: "humanpls · \(job.heading)", autosave: "humanpls.pick",
                                size: job.sections.count > 1 ? NSSize(width: 1020, height: 740) : NSSize(width: 760, height: 700),
                                content: PickRoot(model: model).onExitCommand { model.finish(.cancel) }, onDone: finishNow)
            model.onFinish = { [weak popup] a, t, p in popup?.finish(a, t, p) }
            popup.autoText = { model.text }; popup.autoPicks = { model.picks }
        case .show:
            let model = ShowModel(job: job, waiting: wait)
            popup = PopupWindow(job: job, title: "humanpls · \(job.heading)", autosave: "humanpls.show",
                                size: NSSize(width: 1100, height: 760),
                                content: ShowRoot(model: model).onExitCommand { model.finish(.cancel) }, onDone: finishNow)
            model.onFinish = { [weak popup] a, t in popup?.finish(a, t, nil) }
            popup.autoText = { model.text }
        }
        open[job.id] = popup
        if let auto = Controller.autoAction(env) {
            DispatchQueue.main.async { popup.finish(auto, popup.autoText?() ?? "", popup.autoPicks?()) }
        } else {
            popup.show()
        }
    }

    func finished(job: Job, action: FinishAction, text: String, picks: Picks?, env: ClientEnv, wait: Bool, reply: @escaping (Response) -> Void) {
        if open[job.id]?.finished == true { open[job.id] = nil }
        Cache.stopAll()
        let status: String
        switch action {
        case .cancel: status = "cancelled"
        case .copy: status = "copied"
        case .send: status = "sent"
        }
        history.save(HistoryEntry(job: job, picks: picks, answer: action == .cancel ? nil : text, status: status))
        switch action {
        case .cancel:
            if wait { reply(Response(type: "answer", status: "cancelled")) }
        case .copy:
            Sender.copy(text)
            if wait { reply(Response(type: "answer", answer: text, status: "copied")) }
        case .send:
            if wait { reply(Response(type: "answer", answer: text, status: "sent")) }
            else if !text.isEmpty, Controller.autoAction(env) == nil { Sender.deliver(text, env: env) { _ in } }
        }
    }

    func reopen(ref: String?, env: ClientEnv) -> Response {
        guard let e = history.find(ref) else { return Response(type: "error", message: "nothing to reopen") }
        var job = e.job
        job.createdAt = Date()
        open(job: job, picks: e.picks, env: env, wait: false) { _ in }
        return Response(type: "accepted", message: "reopened \(job.id)")
    }

    func reopenLast() { _ = reopen(ref: nil, env: ClientEnv()) }
}

// MARK: unix socket server

final class Server {
    let fd: Int32
    let controller: Controller

    init(controller: Controller) throws {
        self.controller = controller
        fd = try UnixSocket.listen()
    }

    func start() {
        let f = fd
        Thread.detachNewThread { [weak self] in
            while let c = UnixSocket.accept(f) {
                DispatchQueue.global().async { self?.handle(c) }
            }
        }
    }

    func handle(_ c: Int32) {
        let reader = LineReader(fd: c)
        guard let line = reader.readLine(), let req = try? Coding.decoder().decode(Request.self, from: line) else { close(c); return }
        let ctl = controller
        switch req.cmd {
        case "ping":
            _ = send(c, Response(type: "pong")); close(c)
        case "list":
            _ = send(c, Response(type: "jobs", jobs: HistoryStore().summaries())); close(c)
        case "quit":
            _ = send(c, Response(type: "accepted")); close(c)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        case "reopen":
            Task { @MainActor in
                let r = ctl.reopen(ref: req.ref, env: req.env ?? ClientEnv())
                _ = send(c, r); close(c)
            }
        case "pick", "show":
            guard let job = req.job else { _ = send(c, Response(type: "error", message: "no job")); close(c); return }
            let wait = req.wait
            Task { @MainActor in
                ctl.open(job: job, env: req.env ?? ClientEnv(), wait: wait) { resp in
                    _ = send(c, resp)
                    if resp.type == "answer" || resp.type == "error" || (resp.type == "accepted" && !wait) { close(c) }
                }
            }
        default:
            _ = send(c, Response(type: "error", message: "unknown command \(req.cmd)")); close(c)
        }
    }
}

// MARK: menu bar + app

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = Controller()
    var server: Server?
    var status: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        if UnixSocket.connect() != nil { exit(0) }        // already running
        do { server = try Server(controller: controller); server?.start() }
        catch { FileHandle.standardError.write(Data("humanpls: \(error)\n".utf8)); exit(1) }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = status.button {
            b.image = NSImage(systemSymbolName: "person.crop.circle.badge.questionmark", accessibilityDescription: "humanpls")
        }
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let head = NSMenuItem(title: "humanpls", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())
        let recent = controller.history.all().prefix(12)
        if recent.isEmpty {
            let none = NSMenuItem(title: "No popups yet", action: nil, keyEquivalent: ""); none.isEnabled = false; menu.addItem(none)
        }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        for e in recent {
            let mark = e.status == "sent" || e.status == "copied" ? "✓ " : (e.status == "cancelled" ? "✕ " : "")
            let it = NSMenuItem(title: "\(mark)\(e.job.heading)  ·  \(f.localizedString(for: e.job.createdAt, relativeTo: Date()))",
                                action: #selector(reopenItem(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = e.job.id
            menu.addItem(it)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear history", action: #selector(clearHistory), keyEquivalent: ""); clear.target = self
        menu.addItem(clear)
        let quit = NSMenuItem(title: "Quit humanpls", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc func reopenItem(_ s: NSMenuItem) {
        _ = controller.reopen(ref: s.representedObject as? String, env: ClientEnv())
    }
    @objc func clearHistory() { controller.history.clear() }

    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ n: Notification) { unlink(Paths.socket) }
}

@MainActor var appDelegate: AppDelegate?

@MainActor
enum AppMain {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        appDelegate = AppDelegate()
        app.delegate = appDelegate
        app.run()
    }
}
