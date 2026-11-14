import AppKit

/// Puts the `humanpls` command on the PATH by linking it to the program inside the app.
/// Used by the menu item "Install 'humanpls' command" and by `humanpls install-cli`.
@MainActor
enum CommandLineTool {
    /// The real program inside the app, never a link to it.
    static var executable: String {
        URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath().path
    }
    /// /usr/local/bin is on every Mac's PATH. ~/.local/bin needs no password but is not on the PATH of a fresh Mac.
    static let systemDir = "/usr/local/bin"
    static var userDir: String { NSHomeDirectory() + "/.local/bin" }

    static func link(in dir: String) -> String { (dir as NSString).appendingPathComponent("humanpls") }

    /// The link that already points to this app, if there is one.
    static func installedLink() -> String? {
        [systemDir, userDir].map(link).first { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0)) == executable }
    }

    static func isOnPath(_ dir: String) -> Bool {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains(Substring(dir))
    }

    /// Link the command into `dir`. Replaces an old link. Returns the link path.
    @discardableResult
    static func install(into dir: String) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let l = link(in: dir)
        if (try? fm.destinationOfSymbolicLink(atPath: l)) != nil || fm.fileExists(atPath: l) { try fm.removeItem(atPath: l) }
        try fm.createSymbolicLink(atPath: l, withDestinationPath: executable)
        return l
    }

    /// For the menu: /usr/local/bin if we may write there, else ask for the administrator password once, else ~/.local/bin.
    static func installInteractively() -> (path: String, note: String?) {
        if FileManager.default.isWritableFile(atPath: systemDir), let p = try? install(into: systemDir) { return (p, nil) }
        let cmd = "mkdir -p \(systemDir) && ln -sf '\(executable)' \(link(in: systemDir))"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err == nil { return (link(in: systemDir), nil) }
        // no password given: a link in the home folder works without one
        if let p = try? install(into: userDir) {
            return (p, isOnPath(userDir) ? nil : "\(userDir) is not on your PATH yet. Add this line to ~/.zshrc:\n  export PATH=\"$HOME/.local/bin:$PATH\"")
        }
        return ("", "Could not create the command. Run this in a terminal instead:\n  sudo ln -sf '\(executable)' \(link(in: systemDir))")
    }
}
