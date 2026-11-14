import AppKit
import ApplicationServices
import HumanplsCore

/// Puts the answer into the chat of the terminal that started the popup.
/// 1. tmux: paste into the exact pane and press Enter. No focus change, no permission.
/// 2. Terminal app: bring it to the front, then Cmd+V and Return (needs the Accessibility permission).
/// 3. Otherwise the answer stays on the clipboard.
@MainActor
enum Sender {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Returns true when the text was pasted and sent. Always leaves a copy on the clipboard when it returns false.
    static func deliver(_ text: String, env: ClientEnv, done: @escaping (Bool) -> Void) {
        if let pane = env.tmuxPane, let tmux = env.tmuxPath {
            DispatchQueue.global().async {
                let ok = viaTmux(text, pane: pane, tmux: tmux, socket: env.tmuxSocket)
                DispatchQueue.main.async { if !ok { copy(text) }; done(ok) }
            }
            return
        }
        if let bid = env.bundleId, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            copy(text)
            guard AXIsProcessTrusted() else {
                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
                done(false); return
            }
            app.activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                key(9, cmd: true)       // Cmd+V
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    key(36, cmd: false) // Return
                    done(true)
                }
            }
            return
        }
        copy(text)
        done(false)
    }

    nonisolated static func tmuxRun(_ tmux: String, socket: String?, _ args: [String]) -> Bool {
        var a: [String] = []
        if let s = socket, !s.isEmpty { a += ["-S", s] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmux)
        p.arguments = a + args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    nonisolated static func viaTmux(_ text: String, pane: String, tmux: String, socket: String?) -> Bool {
        guard tmuxRun(tmux, socket: socket, ["set-buffer", "-b", "humanpls", "--", text]) else { return false }
        // -p = bracketed paste, so a multi-line answer arrives as one block
        guard tmuxRun(tmux, socket: socket, ["paste-buffer", "-p", "-d", "-b", "humanpls", "-t", pane]) else { return false }
        usleep(300_000)
        return tmuxRun(tmux, socket: socket, ["send-keys", "-t", pane, "Enter"])
    }

    static func key(_ code: CGKeyCode, cmd: Bool) {
        let src = CGEventSource(stateID: .privateState)
        let flags: CGEventFlags = cmd ? .maskCommand : []
        if cmd { let c = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true); c?.flags = .maskCommand; c?.post(tap: .cghidEventTap) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        if cmd { let c = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false); c?.flags = []; c?.post(tap: .cghidEventTap) }
    }
}
